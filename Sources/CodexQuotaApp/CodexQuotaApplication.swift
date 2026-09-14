import AppKit
import CodexQuotaCore
import Darwin

@main
@MainActor
struct CodexQuotaApplication {
    static func main() {
        Darwin.signal(SIGPIPE, SIG_IGN)

        let application = NSApplication.shared
        let delegate = AppDelegate()

        application.setActivationPolicy(.accessory)
        application.delegate = delegate

        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlayController: QuotaOverlayController?
    private let appUpdater = AppUpdateController()
    private let launchAtLoginCoordinator = LaunchAtLoginCoordinator()
    private let launchAtLoginService = MainAppLaunchAtLoginService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlayController = QuotaOverlayController()
        appUpdater.canInstall = { [weak self] in self?.overlayController?.canInstallUpdate ?? false }
        overlayController?.configureSoftwareUpdates(
            check: { [weak self] in self?.appUpdater.checkForUpdates() },
            state: { [weak self] in (self?.appUpdater.canCheck ?? false, self?.appUpdater.automaticallyUpdates ?? false) },
            setAutomatic: { [weak self] in self?.appUpdater.automaticallyUpdates = $0 }
        )
        appUpdater.start()
        _ = launchAtLoginCoordinator.ensureEnabled(
            using: launchAtLoginService
        )
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        (overlayController?.canTerminateForUpdate ?? true) ? .terminateNow : .terminateCancel
    }
}
