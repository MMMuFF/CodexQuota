import AppKit
import ApplicationServices

@MainActor
private final class Fixture {
    var nodes: [(AXUIElement, [String: Any])] = []
    let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
    lazy var window = node(role: kAXWindowRole, frame: bounds)
    lazy var rail = node(frame: CGRect(x: 0, y: 0, width: 64, height: 800))

    func node(role: String = kAXGroupRole, subrole: String = "", frame: CGRect? = nil) -> AXUIElement {
        let element = AXUIElementCreateApplication(pid_t(900_000 + nodes.count))
        var attributes: [String: Any] = [kAXRoleAttribute: role, kAXSubroleAttribute: subrole]
        if let frame {
            var origin = frame.origin
            var size = frame.size
            attributes[kAXPositionAttribute] = AXValueCreate(.cgPoint, &origin)!
            attributes[kAXSizeAttribute] = AXValueCreate(.cgSize, &size)!
        }
        nodes.append((element, attributes))
        return element
    }

    func set(_ element: AXUIElement, _ key: String, _ value: Any) {
        let index = nodes.firstIndex { CFEqual($0.0, element) }!
        nodes[index].1[key] = value
    }

    func prepare(includeRail: Bool) {
        let sidebar = node(subrole: "AXLandmarkComplementary", frame: CGRect(x: 0, y: 0, width: 320, height: 800))
        let splitter = node(role: kAXSplitterRole, frame: CGRect(x: 319, y: 0, width: 2, height: 800))
        let main = node(subrole: "AXLandmarkMain", frame: CGRect(x: 320, y: 0, width: 680, height: 800))
        set(window, kAXChildrenAttribute, [sidebar, splitter, main])
        let controls = [60, 120, 690, 750].map { y in
            node(role: kAXButtonRole, frame: CGRect(x: 16, y: y, width: 32, height: 32))
        }
        set(rail, kAXChildrenAttribute, controls)
        if includeRail { set(main, kAXChildrenAttribute, [nodeWithRail()]) }
        let application = AXUIElementCreateApplication(NSRunningApplication.current.processIdentifier)
        nodes.append((application, [kAXWindowsAttribute: [window]]))
    }

    func nodeWithRail() -> AXUIElement {
        let container = node()
        set(container, kAXChildrenAttribute, [rail])
        return container
    }

    func locator() -> CodexSidebarLocator {
        CodexSidebarLocator(readAttribute: { [self] element, name in
            nodes.first { CFEqual($0.0, element) }?.1[name as String] as CFTypeRef?
        }, checkAccess: { true }, hitTest: { _, _ in nil })
    }

    var target: LocatedCodexWindow {
        LocatedCodexWindow(application: .current, windowID: 1, frame: bounds, accessibilityFrame: bounds)
    }
}

@main
@MainActor
private struct LocatorTests {
    static func main() {
        let fixture = Fixture()
        fixture.prepare(includeRail: true)
        guard case .vertical = fixture.locator().placement(for: fixture.target) else {
            print("FAIL: legacy sidebar matched before a deeper navigation rail")
            exit(1)
        }
        print("PASS: navigation rail takes precedence over legacy landmarks")

        let transition = Fixture()
        transition.prepare(includeRail: false)
        let locator = transition.locator()
        guard case .hidden = locator.placement(for: transition.target) else { exit(1) }
        transition.set(transition.window, kAXChildrenAttribute, [transition.nodeWithRail()])
        Thread.sleep(forTimeInterval: 0.6)
        guard case .vertical = locator.placement(for: transition.target) else {
            print("FAIL: cached hidden legacy layout prevents rail rediscovery")
            exit(1)
        }
        print("PASS: hidden legacy cache is revalidated after layout changes")

        let blocked = Fixture()
        blocked.prepare(includeRail: true)
        let obstruction = blocked.node(role: kAXButtonRole, frame: CGRect(x: 4, y: 625, width: 20, height: 20))
        let controls = blocked.nodes.first { CFEqual($0.0, blocked.rail) }!.1[kAXChildrenAttribute] as! [AXUIElement]
        blocked.set(blocked.rail, kAXChildrenAttribute, controls + [obstruction])
        guard case .hidden = blocked.locator().placement(for: blocked.target) else {
            print("FAIL: occupied rail slot must remain hidden")
            exit(1)
        }
        print("PASS: navigation rail still avoids occupied slots")

        let denied = CodexSidebarLocator(readAttribute: { _, _ in
            fatalError("Must not read Accessibility attributes without permission")
        }, checkAccess: { false }, hitTest: { _, _ in nil })
        guard case .permissionRequired = denied.placement(for: fixture.target) else { exit(1) }
        print("PASS: missing permission never reads the UI tree")
        print("All 4 real-locator checks passed with synthetic nodes")
    }
}
