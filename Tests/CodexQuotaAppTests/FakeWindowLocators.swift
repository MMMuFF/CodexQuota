import AppKit

// Replace only the external window/AX boundary in the AppKit test executable.
// These tests never inspect the running Codex app or request Accessibility access.
struct LocatedCodexWindow {
    let application: NSRunningApplication
    let windowID: Int
    let frame: CGRect
    let accessibilityFrame: CGRect
}

enum CodexSidebarPlacement {
    case permissionRequired
    case unavailable
    case hidden
    case visible(trailingEdgeX: CGFloat, footerCenterBottomInset: CGFloat?, trailingControlMinX: CGFloat?, accountContentMaxX: CGFloat? = nil)
}

@MainActor
enum CodexWindowLocator {
    static let bundleIdentifier = "test.codexquota.synthetic-target"
    static var testWindow: LocatedCodexWindow?
    static func locateMainWindow() -> LocatedCodexWindow? { testWindow }
}

@MainActor
final class CodexSidebarLocator {
    static var testPlacement: CodexSidebarPlacement = .hidden
    func placement(for window: LocatedCodexWindow) -> CodexSidebarPlacement { Self.testPlacement }
}
