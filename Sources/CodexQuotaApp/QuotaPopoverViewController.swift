import AppKit
import CodexQuotaCore

@MainActor
final class QuotaPopoverViewController: NSViewController {
    var onUseResetCredit: (() -> Void)?
    var onRefresh: (() -> Void)?
    var onQuit: (() -> Void)?
    var onHoverChanged: ((Bool) -> Void)?

    private let summaryLabel = NSTextField(labelWithString: "-- · 读取中")
    private let timeProgressRow = QuotaProgressRowView(
        title: "时间",
        accessibilityLabel: "时间已过"
    )
    private let quotaProgressRow = QuotaProgressRowView(
        title: "额度",
        accessibilityLabel: "额度已用"
    )
    private let forecastLabel = NSTextField(labelWithString: "按周期均速，暂无法估算")
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

        forecastLabel.font = .systemFont(ofSize: 11, weight: .regular)
        forecastLabel.textColor = .secondaryLabelColor
        forecastLabel.lineBreakMode = .byTruncatingTail

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

        let progressStack = NSStackView(views: [timeProgressRow, quotaProgressRow])
        progressStack.orientation = .vertical
        progressStack.alignment = .leading
        progressStack.spacing = 6

        let progressSection = NSStackView(views: [progressStack, forecastLabel])
        progressSection.orientation = .vertical
        progressSection.alignment = .leading
        progressSection.spacing = 6

        let secondaryActions = NSStackView(views: [refreshButton, quitButton])
        secondaryActions.orientation = .horizontal
        secondaryActions.alignment = .centerY
        secondaryActions.spacing = 6

        let actionRow = NSStackView(views: [useButton, NSView(), secondaryActions])
        actionRow.orientation = .horizontal
        actionRow.alignment = .centerY
        actionRow.spacing = 8

        let stack = NSStackView(
            views: [summaryLabel, progressSection, detailStack, freshnessLabel, actionRow]
        )
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
            progressSection.widthAnchor.constraint(equalTo: stack.widthAnchor),
            progressStack.widthAnchor.constraint(equalTo: progressSection.widthAnchor),
            timeProgressRow.widthAnchor.constraint(equalTo: progressStack.widthAnchor),
            quotaProgressRow.widthAnchor.constraint(equalTo: progressStack.widthAnchor),
            forecastLabel.widthAnchor.constraint(equalTo: progressSection.widthAnchor),
            detailStack.widthAnchor.constraint(equalTo: stack.widthAnchor),
            freshnessLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])

        view = root
        preferredContentSize = NSSize(width: 316, height: 230)
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
        updateProgress(QuotaCycleProgress.calculate(for: status))
        forecastLabel.stringValue = QuotaDisplayFormatter.exhaustionForecastText(
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
            updateProgress(nil)
            forecastLabel.stringValue = "按周期均速，暂无法估算"
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

    private func updateProgress(_ progress: QuotaCycleProgress?) {
        timeProgressRow.update(
            fraction: progress?.timeElapsedFraction,
            percent: progress?.timeElapsedPercent
        )
        quotaProgressRow.update(
            fraction: progress?.quotaUsedFraction,
            percent: progress?.quotaUsedPercent
        )
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

private final class QuotaProgressRowView: NSStackView {
    private let titleLabel: NSTextField
    private let progressIndicator = NSProgressIndicator()
    private let percentLabel = NSTextField(labelWithString: "--")
    private let progressAccessibilityLabel: String

    init(title: String, accessibilityLabel: String) {
        titleLabel = NSTextField(labelWithString: title)
        progressAccessibilityLabel = accessibilityLabel
        super.init(frame: .zero)

        orientation = .horizontal
        alignment = .centerY
        spacing = 8

        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.setAccessibilityElement(false)

        progressIndicator.style = .bar
        progressIndicator.controlSize = .small
        progressIndicator.isIndeterminate = false
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 1
        progressIndicator.doubleValue = 0
        progressIndicator.setAccessibilityElement(false)
        progressIndicator.setContentHuggingPriority(.defaultLow, for: .horizontal)

        percentLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        percentLabel.textColor = .secondaryLabelColor
        percentLabel.alignment = .right
        percentLabel.setAccessibilityElement(false)

        addArrangedSubview(titleLabel)
        addArrangedSubview(progressIndicator)
        addArrangedSubview(percentLabel)

        NSLayoutConstraint.activate([
            titleLabel.widthAnchor.constraint(equalToConstant: 32),
            progressIndicator.heightAnchor.constraint(equalToConstant: 8),
            progressIndicator.widthAnchor.constraint(greaterThanOrEqualToConstant: 150),
            percentLabel.widthAnchor.constraint(equalToConstant: 34),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 16),
        ])

        setUnavailable()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(fraction: Double?, percent: Int?) {
        guard let fraction, let percent else {
            setUnavailable()
            return
        }

        progressIndicator.doubleValue = fraction
        percentLabel.stringValue = "\(percent)%"
        setAccessibilityElement(false)
        progressIndicator.setAccessibilityElement(true)
        progressIndicator.setAccessibilityLabel(progressAccessibilityLabel)
        progressIndicator.setAccessibilityValueDescription("\(percent)%")
    }

    private func setUnavailable() {
        progressIndicator.doubleValue = 0
        percentLabel.stringValue = "--"
        progressIndicator.setAccessibilityElement(false)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("\(progressAccessibilityLabel)：暂不可用")
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
