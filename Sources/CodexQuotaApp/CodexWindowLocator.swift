import AppKit
import CodexQuotaCore
import CoreGraphics

struct LocatedCodexWindow {
    let application: NSRunningApplication
    let windowID: Int
    let frame: CGRect
    let accessibilityFrame: CGRect
}

enum CodexWindowLocator {
    static let bundleIdentifier = "com.openai.codex"

    static func runningApplication() -> NSRunningApplication? {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first { !$0.isTerminated }
    }

    static func locateMainWindow() -> LocatedCodexWindow? {
        guard let application = runningApplication(), !application.isHidden else {
            return nil
        }

        let snapshots = windowSnapshots(for: application.processIdentifier)
        guard let mainWindow = CodexOverlayGeometry.mainWindow(in: snapshots) else {
            return nil
        }

        let primaryScreenMaxY = NSScreen.screens.first?.frame.maxY ?? 0
        let appKitFrame = CodexOverlayGeometry.appKitWindowFrame(
            fromCoreGraphics: mainWindow.frame,
            primaryScreenMaxY: primaryScreenMaxY
        )

        return LocatedCodexWindow(
            application: application,
            windowID: mainWindow.windowID,
            frame: appKitFrame,
            accessibilityFrame: mainWindow.frame
        )
    }

    private static func windowSnapshots(for processIdentifier: pid_t) -> [CodexWindowSnapshot] {
        guard let windowInfo = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        return windowInfo.enumerated().compactMap { order, item in
            guard (item[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
                    == processIdentifier,
                  let boundsDictionary = item[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(
                    dictionaryRepresentation: boundsDictionary as CFDictionary
                  ) else {
                return nil
            }

            return CodexWindowSnapshot(
                windowID: (item[kCGWindowNumber as String] as? NSNumber)?.intValue ?? 0,
                frame: frame,
                layer: (item[kCGWindowLayer as String] as? NSNumber)?.intValue ?? -1,
                isOnScreen: (item[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false,
                alpha: (item[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1,
                order: order
            )
        }
    }
}
