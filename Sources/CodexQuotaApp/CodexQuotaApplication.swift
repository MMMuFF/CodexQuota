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
    private let launchAtLoginCoordinator = LaunchAtLoginCoordinator()
    private let launchAtLoginService = MainAppLaunchAtLoginService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlayController = QuotaOverlayController()
        _ = launchAtLoginCoordinator.ensureEnabled(
            using: launchAtLoginService
        )
    }
}
