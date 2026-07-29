import CoreGraphics

public struct CodexWindowSnapshot: Equatable {
    public let windowID: Int
    public let frame: CGRect
    public let layer: Int
    public let isOnScreen: Bool
    public let alpha: Double
    public let order: Int

    public init(
        windowID: Int,
        frame: CGRect,
        layer: Int,
        isOnScreen: Bool,
        alpha: Double,
        order: Int
    ) {
        self.windowID = windowID
        self.frame = frame
        self.layer = layer
        self.isOnScreen = isOnScreen
        self.alpha = alpha
        self.order = order
    }
}

public enum CodexTaskSidebarObservation: Equatable, Sendable {
    case task(trailingEdgeX: CGFloat)
    case temporarilyUnavailable(trailingEdgeX: CGFloat?)
    case nonTask(trailingEdgeX: CGFloat?)
    case sidebarHidden
}

public enum CodexTaskSidebarDecision: Equatable, Sendable {
    case visible(trailingEdgeX: CGFloat)
    case hidden
}

public struct CodexTaskSidebarFooterMetrics: Equatable, Sendable {
    public let centerBottomInset: CGFloat
    public let trailingControlMinX: CGFloat

    public init(centerBottomInset: CGFloat, trailingControlMinX: CGFloat) {
        self.centerBottomInset = centerBottomInset
        self.trailingControlMinX = trailingControlMinX
    }
}

public struct CodexTaskSidebarContinuity: Sendable {
    private var lastTrailingEdgeX: CGFloat?
    private var lastGeometryChangeAt: Double?
    private var hasConfirmedTaskSidebar = false
    private var consecutiveStableNonTaskObservations = 0

    public init() {}

    public mutating func reset() {
        lastTrailingEdgeX = nil
        lastGeometryChangeAt = nil
        hasConfirmedTaskSidebar = false
        consecutiveStableNonTaskObservations = 0
    }

    public mutating func decision(
        for observation: CodexTaskSidebarObservation,
        timestamp: Double
    ) -> CodexTaskSidebarDecision {
        switch observation {
        case let .task(trailingEdgeX):
            _ = updateTrailingEdge(trailingEdgeX, timestamp: timestamp)
            hasConfirmedTaskSidebar = true
            consecutiveStableNonTaskObservations = 0
            return .visible(trailingEdgeX: trailingEdgeX)

        case let .temporarilyUnavailable(trailingEdgeX):
            guard hasConfirmedTaskSidebar else { return .hidden }
            _ = updateTrailingEdge(trailingEdgeX, timestamp: timestamp)
            consecutiveStableNonTaskObservations = 0
            guard let lastTrailingEdgeX else { return .hidden }
            return .visible(trailingEdgeX: lastTrailingEdgeX)

        case let .nonTask(trailingEdgeX):
            guard hasConfirmedTaskSidebar else { return .hidden }
            let geometryChanged = updateTrailingEdge(
                trailingEdgeX,
                timestamp: timestamp
            )
            let isWithinResizeGrace = lastGeometryChangeAt.map {
                timestamp - $0 <= 1.25
            } ?? false
            if geometryChanged || isWithinResizeGrace {
                consecutiveStableNonTaskObservations = 0
            } else {
                consecutiveStableNonTaskObservations += 1
            }

            guard consecutiveStableNonTaskObservations < 2,
                  let lastTrailingEdgeX else {
                reset()
                return .hidden
            }
            return .visible(trailingEdgeX: lastTrailingEdgeX)

        case .sidebarHidden:
            reset()
            return .hidden
        }
    }

    @discardableResult
    private mutating func updateTrailingEdge(
        _ trailingEdgeX: CGFloat?,
        timestamp: Double
    ) -> Bool {
        guard let trailingEdgeX else { return false }
        let geometryChanged = lastTrailingEdgeX.map {
            abs($0 - trailingEdgeX) > 0.5
        } ?? false
        if geometryChanged {
            lastGeometryChangeAt = timestamp
        }
        lastTrailingEdgeX = trailingEdgeX
        return geometryChanged
    }
}

public enum CodexOverlayGeometry {
    public static let horizontalInset: CGFloat = 118
    public static let bottomInset: CGFloat = 19
    public static let badgeSize = CGSize(width: 154, height: 28)
    public static let sidebarTrailingInset: CGFloat = 64
    public static let trailingControlGap: CGFloat = 4
    public static let minimumBadgeWidth: CGFloat = 44
    public static let minimumVisibleSidebarWidth: CGFloat = 180
    private static let transientOverlayRoles: Set<String> = [
        "AXApplicationDialog",
        "AXDialog",
        "AXSheet",
    ]

    public static func mainWindow(in snapshots: [CodexWindowSnapshot]) -> CodexWindowSnapshot? {
        let candidates = snapshots
            .filter {
                $0.isOnScreen
                    && $0.layer == 0
                    && $0.alpha > 0
                    && $0.frame.width >= 600
                    && $0.frame.height >= 400
            }

        guard let largestArea = candidates
            .map({ $0.frame.width * $0.frame.height })
            .max() else {
            return nil
        }

        return candidates
            .filter { $0.frame.width * $0.frame.height >= largestArea * 0.8 }
            .sorted {
                if $0.order != $1.order {
                    return $0.order < $1.order
                }
                return $0.frame.width * $0.frame.height > $1.frame.width * $1.frame.height
            }
            .first
    }

    public static func appKitWindowFrame(
        fromCoreGraphics frame: CGRect,
        primaryScreenMaxY: CGFloat
    ) -> CGRect {
        CGRect(
            x: frame.minX,
            y: primaryScreenMaxY - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }

    public static func isSidebarVisible(
        sidebarFrame: CGRect?,
        within windowFrame: CGRect
    ) -> Bool {
        guard let sidebarFrame else { return false }
        return abs(sidebarFrame.minX - windowFrame.minX) <= 8
            && sidebarFrame.height >= windowFrame.height * 0.75
            && sidebarFrame.width >= minimumVisibleSidebarWidth
            && sidebarFrame.width <= 700
    }

    public static func isMainContentFullWidth(
        mainContentFrame: CGRect?,
        within windowFrame: CGRect
    ) -> Bool {
        guard let mainContentFrame else { return false }
        return abs(mainContentFrame.minX - windowFrame.minX) <= 8
            && mainContentFrame.height >= windowFrame.height * 0.75
            && mainContentFrame.width >= windowFrame.width * 0.9
    }

    public static func isTaskSidebarFooter(
        sidebarFrame: CGRect,
        accountControlFrame: CGRect?,
        trailingButtonFrame: CGRect?
    ) -> Bool {
        taskSidebarFooterMetrics(
            sidebarFrame: sidebarFrame,
            accountControlFrame: accountControlFrame,
            trailingButtonFrame: trailingButtonFrame
        ) != nil
    }

    public static func taskSidebarFooterMetrics(
        sidebarFrame: CGRect,
        accountControlFrame: CGRect?,
        trailingButtonFrame: CGRect?
    ) -> CodexTaskSidebarFooterMetrics? {
        guard let accountControlFrame, let trailingButtonFrame else { return nil }

        let accountBottomGap = sidebarFrame.maxY - accountControlFrame.maxY
        let trailingRightGap = sidebarFrame.maxX - trailingButtonFrame.maxX
        let maximumTrailingWidth = min(
            72,
            max(48, sidebarFrame.width * 0.2)
        )
        let maximumTrailingHeight = min(
            72,
            max(50, accountControlFrame.height * 1.5)
        )
        guard accountControlFrame.minX >= sidebarFrame.minX - 4
            && accountControlFrame.maxX <= sidebarFrame.maxX + 4
            && accountControlFrame.width >= sidebarFrame.width * 0.55
            && accountControlFrame.height >= 28
            && accountControlFrame.height <= 56
            && accountBottomGap >= -4
            && accountBottomGap <= 24
            && trailingButtonFrame.width >= 20
            && trailingButtonFrame.width <= maximumTrailingWidth
            && trailingButtonFrame.height >= 20
            && trailingButtonFrame.height <= maximumTrailingHeight
            && trailingButtonFrame.minX >= accountControlFrame.maxX + 4
            && abs(trailingButtonFrame.midY - accountControlFrame.midY) <= 6
            && trailingRightGap >= -4
            && trailingRightGap <= 20 else {
            return nil
        }

        let footerCenterY = (accountControlFrame.midY + trailingButtonFrame.midY) / 2
        return CodexTaskSidebarFooterMetrics(
            centerBottomInset: sidebarFrame.maxY - footerCenterY,
            trailingControlMinX: trailingButtonFrame.minX
        )
    }

    public static func isTransientAccessibilityOverlay(
        role: String?,
        subrole: String?
    ) -> Bool {
        role.map(transientOverlayRoles.contains) == true
            || subrole.map(transientOverlayRoles.contains) == true
    }

    public static func badgeFrame(
        for windowFrame: CGRect,
        sidebarTrailingX: CGFloat? = nil,
        footerCenterBottomInset: CGFloat? = nil,
        trailingControlMinX: CGFloat? = nil
    ) -> CGRect {
        let windowMaximumRight = windowFrame.maxX - 16
        let constrainedRight = trailingControlMinX.map {
            $0 - trailingControlGap
        } ?? sidebarTrailingX.map {
            $0 - sidebarTrailingInset
        }
        let preferredX = windowFrame.minX + horizontalInset
        let x: CGFloat
        let width: CGFloat
        if let constrainedRight {
            let maximumRight = min(windowMaximumRight, constrainedRight)
            let minimumX = windowFrame.minX + 16
            let effectiveMaximumRight = max(
                maximumRight,
                minimumX + minimumBadgeWidth
            )
            x = max(
                minimumX,
                min(preferredX, effectiveMaximumRight - badgeSize.width)
            )
            width = max(minimumBadgeWidth, effectiveMaximumRight - x)
        } else {
            x = min(
                preferredX,
                windowMaximumRight - minimumBadgeWidth
            )
            width = min(
                badgeSize.width,
                max(minimumBadgeWidth, windowMaximumRight - x)
            )
        }
        let desiredY = footerCenterBottomInset.map {
            windowFrame.minY + $0 - badgeSize.height / 2
        } ?? windowFrame.minY + bottomInset
        let y = min(
            max(desiredY, windowFrame.minY),
            windowFrame.maxY - badgeSize.height
        )

        return CGRect(
            x: x,
            y: y,
            width: width,
            height: badgeSize.height
        )
    }
}
