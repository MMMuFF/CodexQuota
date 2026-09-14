import AppKit
import CodexQuotaCore
import Sparkle

@MainActor
final class AppUpdateController: NSObject, SPUUpdaterDelegate {
    var canInstall: () -> Bool = { false }
    private var pendingInstall: (() -> Void)?
    private var installationTimer: Timer?
    private var requiresAutomaticUpdates = false
    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil
    )

    func start() { controller.startUpdater() }

    var canCheck: Bool { controller.updater.canCheckForUpdates }

    var automaticallyUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates && controller.updater.automaticallyDownloadsUpdates }
        set {
            controller.updater.automaticallyDownloadsUpdates = newValue
            controller.updater.automaticallyChecksForUpdates = newValue
        }
    }

    func checkForUpdates() {
        guard canCheck else { return }
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        guard canInstall() else {
            throw NSError(domain: "CodexQuota.Update", code: 1, userInfo: [
                NSLocalizedDescriptionKey: L("请等待当前操作完成后再检查更新。", "Wait for the current operation to finish before checking for updates.")
            ])
        }
    }

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        deferInstallation(immediateInstallHandler, automatic: true)
        return true
    }

    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        guard !canInstall() else { return false }
        deferInstallation(installHandler, automatic: false)
        return true
    }

    // Wait for credit operations and the detail card to finish before replacing the app.
    func deferInstallation(_ handler: @escaping () -> Void, automatic: Bool) {
        pendingInstall = handler
        requiresAutomaticUpdates = automatic
        installationTimer?.invalidate()
        installationTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.installIfReady() }
        }
    }

    func installIfReady() {
        guard let handler = pendingInstall, canInstall(),
              !requiresAutomaticUpdates || automaticallyUpdates else { return }
        pendingInstall = nil
        installationTimer?.invalidate()
        installationTimer = nil
        handler()
    }

    deinit { installationTimer?.invalidate() }
}
