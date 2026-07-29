import AppKit
import CodexQuotaCore

@MainActor
final class QuotaPopoverViewController: NSViewController {
    var onUseResetCredit: (() -> Void)?
    var onRefresh: (() -> Void)?
    var onQuit: (() -> Void)?
    var onHoverChanged: ((Bool) -> Void)?

    private let summaryLabel = NSTextField(labelWithString: "-- · 读取中")
    private let subscriptionLabel = NSTextField(labelWithString: "会员到期：读取中")
    private let resetCreditLabel = NSTextField(labelWithString: "最早到期券：读取中")
    private let freshnessLabel = NSTextField(labelWithString: "正在连接 Codex…")
    private let useButton = NSButton(title: "使用重置券", target: nil, action: nil)
    private let refreshButton = NSButton(title: "刷新", target: nil, action: nil)
    private let quitButton = NSButton(title: "退出…", target: nil, action: nil)

    private var currentStatus: QuotaStatus?

    override func loadView() {
        let root = HoverVisualEffectView()
        root.material = .popover
        root.blendingMode = .behindWindow
        root.state = .active
        root.onHoverChanged = { [weak self] isInside in
            self?.onHoverChanged?(isInside)
        }

        summaryLabel.font = .monospacedDigitSystemFont(ofSize: 20, weight: .semibold)
        summaryLabel.textColor = .labelColor
        summaryLabel.lineBreakMode = .byTruncatingTail

        for label in [subscriptionLabel, resetCreditLabel] {
            label.font = .systemFont(ofSize: 13, weight: .regular)
            label.textColor = .labelColor
            label.lineBreakMode = .byTruncatingTail
        }

        freshnessLabel.font = .systemFont(ofSize: 11, weight: .regular)
        freshnessLabel.textColor = .secondaryLabelColor
        freshnessLabel.lineBreakMode = .byTruncatingTail

        useButton.bezelStyle = .rounded
        useButton.controlSize = .regular
        useButton.target = self
        useButton.action = #selector(useResetCredit)
        useButton.isEnabled = false

        refreshButton.bezelStyle = .rounded
        refreshButton.controlSize = .small
        refreshButton.target = self
        refreshButton.action = #selector(refresh)

        quitButton.bezelStyle = .rounded
        quitButton.controlSize = .small
        quitButton.target = self
        quitButton.action = #selector(quit)

        let detailStack = NSStackView(views: [subscriptionLabel, resetCreditLabel])
        detailStack.orientation = .vertical
        detailStack.alignment = .leading
        detailStack.spacing = 7

        let secondaryActions = NSStackView(views: [refreshButton, quitButton])
        secondaryActions.orientation = .horizontal
        secondaryActions.alignment = .centerY
        secondaryActions.spacing = 6

        let actionRow = NSStackView(views: [useButton, NSView(), secondaryActions])
        actionRow.orientation = .horizontal
        actionRow.alignment = .centerY
        actionRow.spacing = 8

        let stack = NSStackView(views: [summaryLabel, detailStack, freshnessLabel, actionRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 11
        stack.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 15),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14),
            actionRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            detailStack.widthAnchor.constraint(equalTo: stack.widthAnchor),
            freshnessLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])

        view = root
        preferredContentSize = NSSize(width: 316, height: 166)
    }

    func showLoading(previousStatus: QuotaStatus?) {
        refreshButton.isEnabled = false
        useButton.isEnabled = false
        freshnessLabel.stringValue = previousStatus == nil ? "正在连接 Codex…" : "正在刷新…"
    }

    func update(status: QuotaStatus, timeZone: TimeZone = .current) {
        currentStatus = status
        summaryLabel.stringValue = QuotaDisplayFormatter.hoverTitle(for: status, timeZone: timeZone)
        subscriptionLabel.stringValue = QuotaDisplayFormatter.subscriptionExpirationText(
            for: status,
            timeZone: timeZone
        )
        resetCreditLabel.stringValue = QuotaDisplayFormatter.resetCreditDetailText(
            for: status,
            timeZone: timeZone
        )

        let actionState = QuotaDisplayFormatter.resetCreditActionState(
            availableCount: status.accountFingerprint == nil
                ? nil
                : status.resetCreditsAvailableCount
        )
        useButton.title = actionState.title
        useButton.isEnabled = actionState.isEnabled
        refreshButton.isEnabled = true
        freshnessLabel.stringValue = QuotaDisplayFormatter.freshnessText(for: status)
    }

    func showError(hasCachedStatus: Bool) {
        refreshButton.isEnabled = true
        if hasCachedStatus {
            freshnessLabel.stringValue = "刷新失败，当前显示上次结果"
        } else {
            summaryLabel.stringValue = "-- · 读取失败"
            subscriptionLabel.stringValue = "会员到期：暂不可用"
            resetCreditLabel.stringValue = "重置券：暂不可用"
            freshnessLabel.stringValue = "请确认 Codex 已登录后重试"
            useButton.title = "重置券暂不可用"
            useButton.isEnabled = false
        }
    }

    func setConsuming(_ consuming: Bool) {
        let actionState = QuotaDisplayFormatter.resetCreditActionState(
            availableCount: currentStatus?.accountFingerprint == nil
                ? nil
                : currentStatus?.resetCreditsAvailableCount
        )
        useButton.isEnabled = !consuming && actionState.isEnabled
        useButton.title = consuming ? "正在重置…" : actionState.title
        refreshButton.isEnabled = !consuming
        freshnessLabel.stringValue = consuming ? "正在安全使用 1 张重置券…" : freshnessLabel.stringValue
    }

    func showActionMessage(_ message: String) {
        freshnessLabel.stringValue = message
    }

    @objc private func useResetCredit() {
        onUseResetCredit?()
    }

    @objc private func refresh() {
        onRefresh?()
    }

    @objc private func quit() {
        onQuit?()
    }
}

private final class HoverVisualEffectView: NSVisualEffectView {
    var onHoverChanged: ((Bool) -> Void)?
    private var hoverTrackingArea: NSTrackingArea?

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
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
    }
}
