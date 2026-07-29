import AppKit

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
        level = .floating
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
    var onHoverChanged: ((Bool) -> Void)?
    var onActivate: (() -> Void)?

    private let label = NSTextField(labelWithString: "-- · 读取中")
    private var hoverTrackingArea: NSTrackingArea?
    private var isHovered = false
    private var isExpanded = false
    private var needsAttention = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    func update(title: String, tooltip: String) {
        label.stringValue = title
        setAccessibilityLabel("Codex 额度。\(tooltip)")
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
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }

        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
        super.updateTrackingAreas()
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

        guard needsAttention || isHovered || isExpanded else { return }
        let fillColor = needsAttention
            ? NSColor.systemOrange.withAlphaComponent(0.16)
            : NSColor.labelColor.withAlphaComponent(0.065)
        fillColor.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7).fill()
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
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Codex 额度读取中")
    }
}
