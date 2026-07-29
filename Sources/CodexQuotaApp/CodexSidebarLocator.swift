import AppKit
import ApplicationServices
import CodexQuotaCore

enum CodexSidebarPlacement {
    case permissionRequired
    case unavailable
    case hidden
    case visible(
        trailingEdgeX: CGFloat,
        footerCenterBottomInset: CGFloat?,
        trailingControlMinX: CGFloat?
    )
}

@MainActor
final class CodexSidebarLocator {
    private enum TaskFooterHitResult: Equatable {
        case task(metrics: CodexTaskSidebarFooterMetrics)
        case nonTask
        case obscured
        case unavailable
    }

    private enum AnchorEdge {
        case middle
        case maximum
    }

    private struct Anchor {
        let element: AXUIElement
        let edge: AnchorEdge
    }

    private struct SidebarElements {
        let sidebar: AXUIElement
        let anchor: Anchor?
        let mainContent: AXUIElement?
    }

    private enum SearchResult {
        case elements(SidebarElements)
        case hidden
        case unavailable
    }

    private let searchRetryInterval: TimeInterval = 0.5
    private let maximumSearchNodes = 3_000

    private var cachedProcessIdentifier: pid_t?
    private var cachedWindowID: Int?
    private var cachedElements: SidebarElements?
    private var lastSearchAt = Date.distantPast
    private var taskSidebarContinuity = CodexTaskSidebarContinuity()
    private var lastFooterMetrics: CodexTaskSidebarFooterMetrics?
    private var didRequestAccess = false

    func placement(for window: LocatedCodexWindow) -> CodexSidebarPlacement {
        guard accessibilityIsAvailable() else {
            taskSidebarContinuity.reset()
            return .permissionRequired
        }

        let processIdentifier = window.application.processIdentifier
        if cachedProcessIdentifier != processIdentifier || cachedWindowID != window.windowID {
            cachedProcessIdentifier = processIdentifier
            cachedWindowID = window.windowID
            cachedElements = nil
            lastSearchAt = .distantPast
            taskSidebarContinuity.reset()
            lastFooterMetrics = nil
        }

        if let cachedElements {
            if let placement = placement(
                for: cachedElements,
                windowFrame: window.accessibilityFrame
            ) {
                return placement
            }
            self.cachedElements = nil
        }

        let now = Date()
        guard now.timeIntervalSince(lastSearchAt) >= searchRetryInterval else {
            return resolve(.temporarilyUnavailable(trailingEdgeX: nil))
        }
        lastSearchAt = now

        switch search(
            processIdentifier: processIdentifier,
            targetFrame: window.accessibilityFrame
        ) {
        case let .elements(elements):
            cachedElements = elements
            guard let placement = placement(
                for: elements,
                windowFrame: window.accessibilityFrame
            ) else {
                return resolve(.temporarilyUnavailable(trailingEdgeX: nil))
            }
            return placement
        case .hidden:
            return resolve(.sidebarHidden)
        case .unavailable:
            return resolve(.temporarilyUnavailable(trailingEdgeX: nil))
        }
    }

    private func accessibilityIsAvailable() -> Bool {
        if AXIsProcessTrusted() {
            return true
        }

        if !didRequestAccess {
            didRequestAccess = true
            let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            let options = [promptKey: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        return false
    }

    private func search(
        processIdentifier: pid_t,
        targetFrame: CGRect
    ) -> SearchResult {
        let application = AXUIElementCreateApplication(processIdentifier)
        guard let windows = attribute(
            application,
            kAXWindowsAttribute as CFString
        ) as? [AXUIElement],
              let targetWindow = windows.min(by: {
                  frameDistance(frame(of: $0), targetFrame)
                      < frameDistance(frame(of: $1), targetFrame)
              }),
              frameDistance(frame(of: targetWindow), targetFrame) < 120 else {
            return .unavailable
        }

        var queue: [(element: AXUIElement, depth: Int)] = [(targetWindow, 0)]
        var cursor = 0
        var anchor: Anchor?
        var sidebar: AXUIElement?
        var mainContent: AXUIElement?

        while cursor < queue.count && cursor < maximumSearchNodes {
            let item = queue[cursor]
            cursor += 1

            let role = stringAttribute(item.element, kAXRoleAttribute as CFString)
            if anchor == nil,
               role == kAXSplitterRole as String,
               let elementFrame = frame(of: item.element),
               isPlausibleSplitter(elementFrame, for: targetFrame) {
                anchor = Anchor(element: item.element, edge: .middle)
            }

            let subrole = stringAttribute(item.element, kAXSubroleAttribute as CFString)
            if sidebar == nil,
               subrole == "AXLandmarkComplementary",
               let elementFrame = frame(of: item.element),
               isSidebarCandidate(elementFrame, for: targetFrame) {
                sidebar = item.element
            }

            if mainContent == nil,
               subrole == "AXLandmarkMain",
               let elementFrame = frame(of: item.element),
               isMainContentCandidate(elementFrame, for: targetFrame) {
                mainContent = item.element
            }

            if let sidebar, let anchor, let mainContent {
                return .elements(
                    SidebarElements(
                        sidebar: sidebar,
                        anchor: anchor,
                        mainContent: mainContent
                    )
                )
            }

            if item.depth < 50,
               let children = attribute(
                   item.element,
                   kAXChildrenAttribute as CFString
               ) as? [AXUIElement] {
                queue.append(contentsOf: children.map { ($0, item.depth + 1) })
            }
        }

        if cursor >= maximumSearchNodes, cursor < queue.count {
            return .unavailable
        }
        if let sidebar {
            return .elements(
                SidebarElements(
                    sidebar: sidebar,
                    anchor: anchor,
                    mainContent: mainContent
                )
            )
        }
        if CodexOverlayGeometry.isMainContentFullWidth(
            mainContentFrame: mainContent.flatMap(frame(of:)),
            within: targetFrame
        ) {
            return .hidden
        }
        return .unavailable
    }

    private func placement(
        for elements: SidebarElements,
        windowFrame: CGRect
    ) -> CodexSidebarPlacement? {
        let sidebarFrame = frame(of: elements.sidebar)
        if CodexOverlayGeometry.isSidebarVisible(
            sidebarFrame: sidebarFrame,
            within: windowFrame
        ), let sidebarFrame {
            let currentTrailingEdgeX: CGFloat
            if let anchor = elements.anchor,
               let edge = trailingEdgeX(of: anchor),
               isPlausible(edgeX: edge, for: windowFrame) {
                currentTrailingEdgeX = edge
            } else {
                currentTrailingEdgeX = sidebarFrame.maxX
            }

            let footerResult = hitTestTaskSidebarFooter(sidebarFrame: sidebarFrame)
            let observation: CodexTaskSidebarObservation
            switch footerResult {
            case let .task(metrics):
                lastFooterMetrics = metrics
                observation = .task(trailingEdgeX: currentTrailingEdgeX)
            case .nonTask:
                observation = .nonTask(trailingEdgeX: currentTrailingEdgeX)
            case .obscured, .unavailable:
                observation = .temporarilyUnavailable(
                    trailingEdgeX: currentTrailingEdgeX
                )
            }
            let resolvedPlacement = resolve(observation)
            if case .task = footerResult {
                return resolvedPlacement
            }
            if case .visible = resolvedPlacement {
                cachedElements = nil
                lastSearchAt = .distantPast
            }
            return resolvedPlacement
        }

        if CodexOverlayGeometry.isMainContentFullWidth(
            mainContentFrame: elements.mainContent.flatMap(frame(of:)),
            within: windowFrame
        ) {
            return resolve(.sidebarHidden)
        }
        return sidebarFrame == nil
            ? nil
            : resolve(.temporarilyUnavailable(trailingEdgeX: nil))
    }

    private func hitTestTaskSidebarFooter(sidebarFrame: CGRect) -> TaskFooterHitResult {
        guard let processIdentifier = cachedProcessIdentifier else { return .unavailable }
        let application = AXUIElementCreateApplication(processIdentifier)
        let footerMidY = sidebarFrame.maxY - 32
        let accountPoint = CGPoint(x: sidebarFrame.minX + 42, y: footerMidY)
        let trailingPoint = CGPoint(x: sidebarFrame.maxX - 24, y: footerMidY)

        guard let accountHit = element(at: accountPoint, in: application),
              let trailingHit = element(at: trailingPoint, in: application) else {
            return .unavailable
        }
        guard let accountControl = ancestor(
            of: accountHit,
            withAnyRole: [kAXPopUpButtonRole as String]
        ), let trailingButton = ancestor(
            of: trailingHit,
            withAnyRole: [
                kAXButtonRole as String,
                kAXPopUpButtonRole as String,
            ]
        ) else {
            if hasTransientOverlayAncestor(accountHit)
                || hasTransientOverlayAncestor(trailingHit) {
                return .obscured
            }
            return .nonTask
        }

        guard let accountFrame = frame(of: accountControl),
              let trailingFrame = frame(of: trailingButton) else {
            return .unavailable
        }
        guard let metrics = CodexOverlayGeometry.taskSidebarFooterMetrics(
            sidebarFrame: sidebarFrame,
            accountControlFrame: accountFrame,
            trailingButtonFrame: trailingFrame
        ) else {
            return .nonTask
        }
        return .task(metrics: metrics)
    }

    private func hasTransientOverlayAncestor(_ element: AXUIElement) -> Bool {
        var current = element
        for _ in 0..<16 {
            if CodexOverlayGeometry.isTransientAccessibilityOverlay(
                role: stringAttribute(current, kAXRoleAttribute as CFString),
                subrole: stringAttribute(current, kAXSubroleAttribute as CFString)
            ) {
                return true
            }
            guard let rawParent = attribute(
                current,
                kAXParentAttribute as CFString
            ) else {
                return false
            }
            current = unsafeBitCast(rawParent, to: AXUIElement.self)
        }
        return false
    }

    private func element(
        at point: CGPoint,
        in application: AXUIElement
    ) -> AXUIElement? {
        var element: AXUIElement?
        return AXUIElementCopyElementAtPosition(
            application,
            Float(point.x),
            Float(point.y),
            &element
        ) == .success ? element : nil
    }

    private func ancestor(
        of element: AXUIElement,
        withAnyRole expectedRoles: Set<String>
    ) -> AXUIElement? {
        var current = element
        for _ in 0..<8 {
            if let role = stringAttribute(current, kAXRoleAttribute as CFString),
               expectedRoles.contains(role) {
                return current
            }
            guard let rawParent = attribute(
                current,
                kAXParentAttribute as CFString
            ) else {
                return nil
            }
            current = unsafeBitCast(rawParent, to: AXUIElement.self)
        }
        return nil
    }

    private func resolve(
        _ observation: CodexTaskSidebarObservation
    ) -> CodexSidebarPlacement {
        switch taskSidebarContinuity.decision(
            for: observation,
            timestamp: Date().timeIntervalSinceReferenceDate
        ) {
        case let .visible(trailingEdgeX):
            return .visible(
                trailingEdgeX: trailingEdgeX,
                footerCenterBottomInset: lastFooterMetrics?.centerBottomInset,
                trailingControlMinX: lastFooterMetrics?.trailingControlMinX
            )
        case .hidden:
            lastFooterMetrics = nil
            return .hidden
        }
    }

    private func trailingEdgeX(of anchor: Anchor) -> CGFloat? {
        guard let elementFrame = frame(of: anchor.element) else { return nil }
        switch anchor.edge {
        case .middle:
            return elementFrame.midX.rounded(.down)
        case .maximum:
            return elementFrame.maxX
        }
    }

    private func isPlausibleSplitter(_ frame: CGRect, for windowFrame: CGRect) -> Bool {
        frame.height >= windowFrame.height * 0.75
            && isPlausible(edgeX: frame.midX, for: windowFrame)
    }

    private func isSidebarCandidate(_ frame: CGRect, for windowFrame: CGRect) -> Bool {
        abs(frame.minX - windowFrame.minX) <= 8
            && frame.height >= windowFrame.height * 0.75
            && frame.width <= 700
    }

    private func isMainContentCandidate(_ frame: CGRect, for windowFrame: CGRect) -> Bool {
        frame.minX >= windowFrame.minX - 8
            && frame.maxX <= windowFrame.maxX + 8
            && frame.height >= windowFrame.height * 0.75
    }

    private func isPlausible(edgeX: CGFloat, for windowFrame: CGRect) -> Bool {
        edgeX >= windowFrame.minX + 180
            && edgeX <= min(windowFrame.minX + 700, windowFrame.maxX - 100)
    }

    private func frameDistance(_ candidate: CGRect?, _ target: CGRect) -> CGFloat {
        guard let candidate else { return .greatestFiniteMagnitude }
        return abs(candidate.minX - target.minX)
            + abs(candidate.minY - target.minY)
            + abs(candidate.width - target.width)
            + abs(candidate.height - target.height)
    }

    private func attribute(_ element: AXUIElement, _ name: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name, &value) == .success
            ? value
            : nil
    }

    private func stringAttribute(_ element: AXUIElement, _ name: CFString) -> String? {
        attribute(element, name) as? String
    }

    private func pointAttribute(_ element: AXUIElement, _ name: CFString) -> CGPoint? {
        guard let raw = attribute(element, name),
              CFGetTypeID(raw) == AXValueGetTypeID() else {
            return nil
        }
        let value = unsafeBitCast(raw, to: AXValue.self)
        guard AXValueGetType(value) == .cgPoint else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value, .cgPoint, &point) ? point : nil
    }

    private func sizeAttribute(_ element: AXUIElement, _ name: CFString) -> CGSize? {
        guard let raw = attribute(element, name),
              CFGetTypeID(raw) == AXValueGetTypeID() else {
            return nil
        }
        let value = unsafeBitCast(raw, to: AXValue.self)
        guard AXValueGetType(value) == .cgSize else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value, .cgSize, &size) ? size : nil
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        guard let origin = pointAttribute(element, kAXPositionAttribute as CFString),
              let size = sizeAttribute(element, kAXSizeAttribute as CFString) else {
            return nil
        }
        return CGRect(origin: origin, size: size)
    }
}
