import AppKit
import CodexQuotaCore

@MainActor
final class QuotaOverlayPanel: NSPanel {
    let chipView = QuotaChipView()

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 154, height: 28)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        contentView = chipView
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .normal
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        animationBehavior = .none
        isReleasedWhenClosed = false
        isMovable = false
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class QuotaChipView: NSView {
    private static let leadingInset: CGFloat = 4
    private static let trailingInset: CGFloat = 2
    var onHoverChanged: ((Bool) -> Void)?
    var onActivate: (() -> Void)?

    private let label = NSTextField(labelWithString: "-- · 读取中")
    private var fullTitle = "-- · 读取中"
    private var hoverTrackingArea: NSTrackingArea?
    private var isHovered = false
    private var isExpanded = false
    private var needsAttention = false
    private var usageDeviation: QuotaUsageDeviation?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    func update(
        title: String,
        tooltip: String,
        usageDeviation: QuotaUsageDeviation?
    ) {
        fullTitle = title
        updateFittedTitle()
        let deviationChanged = self.usageDeviation != usageDeviation
        self.usageDeviation = usageDeviation
        let deviationDescription = usageDeviation.map {
            "。\(QuotaDisplayFormatter.usageDeviationAccessibilityText($0))"
        } ?? ""
        let accessibilityText = "Codex 额度。\(tooltip)\(deviationDescription)"
        if accessibilityLabel() != accessibilityText { setAccessibilityLabel(accessibilityText) }
        if deviationChanged { needsDisplay = true }
    }

    override func layout() {
        super.layout()
        updateFittedTitle()
    }

    private func updateFittedTitle() {
        let compactTitle = fullTitle
            .replacingOccurrences(of: "月", with: "/")
            .replacingOccurrences(of: "日", with: "")
            .replacingOccurrences(of: " · ", with: "·")
        let percentTitle = fullTitle.components(separatedBy: " · ").first ?? fullTitle
        let candidates = [fullTitle, compactTitle, percentTitle]
        guard let measuringCell = label.cell?.copy() as? NSTextFieldCell else { return }
        let fittedTitle = candidates.first { candidate in
            measuringCell.stringValue = candidate
            return measuringCell.cellSize.width <= max(0, bounds.width - Self.leadingInset - Self.trailingInset)
        } ?? percentTitle
        if label.stringValue != fittedTitle {
            label.stringValue = fittedTitle
            needsDisplay = true
        }
    }

    func setExpanded(_ expanded: Bool) {
        isExpanded = expanded
        needsDisplay = true
    }

    func setNeedsAttention(_ attention: Bool) {
        needsAttention = attention
        label.textColor = attention ? .labelColor : .secondaryLabelColor
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // inVisibleRect follows resizing automatically; re-registering can retrigger entry.
        guard hoverTrackingArea == nil else { return }

        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
        onHoverChanged?(false)
    }

    override func mouseDown(with event: NSEvent) {
        onActivate?()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if needsAttention || isHovered || isExpanded {
            let fillColor = needsAttention
                ? NSColor.systemOrange.withAlphaComponent(0.16)
                : NSColor.labelColor.withAlphaComponent(0.065)
            fillColor.setFill()
            NSBezierPath(
                roundedRect: bounds.insetBy(dx: 1, dy: 1),
                xRadius: 7,
                yRadius: 7
            ).fill()
        }

        guard let usageDeviation, !needsAttention else { return }

        let underlineColor: NSColor
        switch usageDeviation.band {
        case .within25:
            underlineColor = (label.textColor ?? .secondaryLabelColor)
                .withAlphaComponent(0.30)
        case .over25:
            underlineColor = .systemOrange.withAlphaComponent(0.42)
        case .over50:
            underlineColor = .systemRed.withAlphaComponent(0.40)
        }

        let underlineWidth = min(
            ceil(label.intrinsicContentSize.width),
            label.frame.width
        )
        guard underlineWidth > 0 else { return }
        let underlineRect = NSRect(
            x: label.frame.midX - underlineWidth / 2,
            y: max(bounds.minY + 2.5, label.frame.minY - 1.5),
            width: underlineWidth,
            height: 1
        )
        underlineColor.setFill()
        NSBezierPath(
            roundedRect: underlineRect,
            xRadius: 0.5,
            yRadius: 0.5
        ).fill()
    }

    private func configureView() {
        wantsLayer = true

        label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.leadingInset),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.trailingInset),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Codex 额度读取中")
    }
}
