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

    private let label = NSTextField(labelWithString: L("-- · 读取中", "-- · Loading"))
    private var fullTitle = L("-- · 读取中", "-- · Loading")
    private var hoverTrackingArea: NSTrackingArea?
    private var isHovered = false
    private var isExpanded = false
    private var needsAttention = false
    private var usageDeviation: QuotaUsageDeviation?
    private var labelConstraints: [NSLayoutConstraint] = []
    var isVertical: Bool { bounds.height >= 64 && bounds.width <= 88 }
    var preferredPopoverEdge: NSRectEdge { isVertical ? .maxX : .maxY }

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
        let accessibilityText = L("Codex 额度。\(tooltip)\(deviationDescription)", "Codex quota. \(tooltip)\(deviationDescription)")
        if accessibilityLabel() != accessibilityText { setAccessibilityLabel(accessibilityText) }
        if deviationChanged { needsDisplay = true }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateFittedTitle()
    }

    private func updateFittedTitle() {
        var compactTitle = fullTitle
            .replacingOccurrences(of: "月", with: "/")
            .replacingOccurrences(of: "([0-9])日", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: " · ", with: "·")
        for (index, month) in ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"].enumerated() {
            compactTitle = compactTitle.replacingOccurrences(of: "\(month) ", with: "\(index + 1)/")
        }
        label.maximumNumberOfLines = isVertical ? 3 : 1
        if isVertical {
            if labelConstraints.first?.isActive == true { NSLayoutConstraint.deactivate(labelConstraints) }
            label.translatesAutoresizingMaskIntoConstraints = true
            let lines = Array(compactTitle.components(separatedBy: "·").prefix(3))
            let text = lines.joined(separator: "\n")
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineSpacing = 2
            paragraph.lineBreakMode = .byClipping
            let percent = lines.first ?? ""
            let percentFont = [15.0, 13.0, 11.0].map {
                NSFont.monospacedDigitSystemFont(ofSize: $0, weight: .semibold)
            }.first { (percent as NSString).size(withAttributes: [.font: $0]).width <= bounds.width - 8 }
                ?? .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
            let attributed = NSMutableAttributedString(string: text, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
                .paragraphStyle: paragraph,
                .foregroundColor: needsAttention ? NSColor.labelColor : NSColor.secondaryLabelColor,
            ])
            attributed.addAttribute(.font, value: percentFont,
                                    range: NSRange(location: 0, length: percent.utf16.count))
            if !label.attributedStringValue.isEqual(to: attributed) {
                label.attributedStringValue = attributed
                needsDisplay = true
            }
            let height = min(ceil(label.intrinsicContentSize.height), bounds.height - 8)
            label.frame = NSRect(x: 1, y: (bounds.height - height) / 2,
                                 width: bounds.width - 2, height: height)
            return
        }
        label.translatesAutoresizingMaskIntoConstraints = false
        if labelConstraints.first?.isActive == false { NSLayoutConstraint.activate(labelConstraints) }
        // Reset multiline font runs when returning to the legacy horizontal footer.
        label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        let percentTitle = fullTitle.components(separatedBy: " · ").first ?? fullTitle
        let dateTitle = compactTitle.components(separatedBy: "·").prefix(2).joined(separator: "·")
        let candidates = [fullTitle, compactTitle, dateTitle, percentTitle]
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
        if isVertical { updateFittedTitle() }
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
        labelConstraints = [
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.leadingInset),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.trailingInset),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ]
        NSLayoutConstraint.activate(labelConstraints)

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(L("Codex 额度读取中", "Loading Codex quota"))
    }
}
