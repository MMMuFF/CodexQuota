import AppKit
import CodexQuotaCore

@MainActor
final class QuotaPopoverViewController: NSViewController {
    var onUseResetCredit: (() -> Void)?
    var onRefresh: (() -> Void)?
    var onQuit: (() -> Void)?
    var onHoverChanged: ((Bool) -> Void)?
    var onAutomaticResetChanged: ((Bool) -> Void)?

    private let summaryLabel = NSTextField(labelWithString: "--")
    private let resetDateLabel = NSTextField(labelWithString: "重置时间读取中")
    private let resetCountdownLabel = NSTextField(labelWithString: "--天后重置")
    private let subscriptionCaption = NSTextField(labelWithString: "会员到期")
    private let creditCaption = NSTextField(labelWithString: "重置券")
    private let timeProgressRow = QuotaProgressRowView(
        title: "时间已过",
        accessibilityLabel: "时间已过"
    )
    private let quotaProgressRow = QuotaProgressRowView(
        title: "额度已用",
        accessibilityLabel: "额度已用"
    )
    private let forecastLabel = NSTextField(labelWithString: "按周期均速，暂无法估算")
    private let subscriptionLabel = NSTextField(labelWithString: "会员到期：读取中")
    private let resetCreditLabel = NSTextField(labelWithString: "最早到期券：读取中")
    private let freshnessLabel = NSTextField(labelWithString: "正在连接 Codex…")
    private let publicResetLabel = NSTextField(wrappingLabelWithString: "Tibo 重置：读取中…")
    private let publicResetLatestLabel = NSTextField(wrappingLabelWithString: "最近公告：读取中…")
    private let publicResetInfoLabel = NSTextField(labelWithString: "· 本机时间")
    private let publicResetWarningLabel = NSTextField(labelWithString: "")
    private let publicResetSourceButton = NSButton(title: "查看来源", target: nil, action: nil)
    private let automaticResetCheckbox = NSButton(
        checkboxWithTitle: "临期自动使用重置券", target: nil, action: nil
    )
    private let useButton = NSButton(title: "使用重置券", target: nil, action: nil)
    private let refreshButton = NSButton(title: "刷新", target: nil, action: nil)
    private let moreButton = NSButton(title: "更多", target: nil, action: nil)

    private var currentStatus: QuotaStatus?
    private var publicResetStatus: PublicResetStatus?
    private var publicResetFailed = false
    private var publicResetSourceURL: URL?

    override func loadView() {
        let root = HoverVisualEffectView()
        root.material = .popover
        root.blendingMode = .behindWindow
        root.state = .active
        root.onHoverChanged = { [weak self] isInside in
            self?.onHoverChanged?(isInside)
        }

        summaryLabel.font = .monospacedDigitSystemFont(ofSize: 30, weight: .semibold)
        summaryLabel.textColor = .labelColor
        summaryLabel.lineBreakMode = .byTruncatingTail

        for label in [subscriptionLabel, resetCreditLabel, subscriptionCaption, creditCaption] {
            label.font = .systemFont(ofSize: 12, weight: .regular)
            label.textColor = .labelColor
            label.lineBreakMode = .byTruncatingTail
        }
        for label in [subscriptionLabel, resetCreditLabel, resetDateLabel, resetCountdownLabel] {
            label.alignment = .right
        }
        for label in [resetDateLabel, resetCountdownLabel] {
            label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            label.textColor = .secondaryLabelColor
        }
        resetCountdownLabel.font = .systemFont(ofSize: 12, weight: .medium)
        resetCountdownLabel.textColor = .labelColor

        freshnessLabel.font = .systemFont(ofSize: 11, weight: .regular)
        freshnessLabel.textColor = .secondaryLabelColor
        freshnessLabel.lineBreakMode = .byTruncatingTail

        forecastLabel.font = .systemFont(ofSize: 11, weight: .regular)
        forecastLabel.textColor = .secondaryLabelColor
        forecastLabel.lineBreakMode = .byTruncatingTail

        for label in [publicResetLabel, publicResetLatestLabel, publicResetInfoLabel, publicResetWarningLabel] {
            label.font = .systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
            label.maximumNumberOfLines = 2
            label.lineBreakMode = .byTruncatingTail
        }
        publicResetLabel.font = .systemFont(ofSize: 12)
        publicResetLabel.textColor = .labelColor
        publicResetInfoLabel.toolTip = "本机时区：\(TimeZone.autoupdatingCurrent.identifier)\nCodex Resets · 第三方公告追踪"
        publicResetInfoLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        publicResetWarningLabel.isHidden = true
        publicResetSourceButton.bezelStyle = .inline
        publicResetSourceButton.controlSize = .small
        publicResetSourceButton.isEnabled = false
        publicResetSourceButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        publicResetSourceButton.target = self
        publicResetSourceButton.action = #selector(openPublicResetSource)
        let publicResetSection = verticalStack([
            publicResetLabel, row(publicResetLatestLabel, publicResetSourceButton), publicResetWarningLabel
        ], spacing: 6)

        useButton.bezelStyle = .rounded
        useButton.controlSize = .regular
        useButton.target = self
        useButton.action = #selector(useResetCredit)
        useButton.isEnabled = false

        refreshButton.bezelStyle = .rounded
        refreshButton.controlSize = .small
        refreshButton.target = self
        refreshButton.action = #selector(refresh)

        moreButton.target = self
        moreButton.action = #selector(showMoreMenu)
        let menu = NSMenu()
        let quitItem = NSMenuItem(title: "退出…", action: #selector(quit), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)
        moreButton.menu = menu
        for (button, symbol, help) in [
            (refreshButton, "arrow.clockwise", "刷新额度与公共公告"),
            (moreButton, "ellipsis", "更多操作"),
            (publicResetSourceButton, "arrow.up.right", "查看公告来源")
        ] {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: help)
            button.imagePosition = .imageOnly
            button.isBordered = false
            button.toolTip = help
            button.setAccessibilityLabel(help)
            button.widthAnchor.constraint(equalToConstant: 24).isActive = true
            button.heightAnchor.constraint(equalToConstant: 22).isActive = true
        }

        automaticResetCheckbox.font = .systemFont(ofSize: 11)
        automaticResetCheckbox.state = .off
        automaticResetCheckbox.isEnabled = false
        automaticResetCheckbox.target = self
        automaticResetCheckbox.action = #selector(automaticResetChanged)
        automaticResetCheckbox.toolTip = "仅对此账户生效：最早到期券进入最后 30 分钟时自动尝试使用 1 张。需要应用运行且电脑保持唤醒联网。"

        let balance = NSTextField(labelWithString: "剩余")
        balance.font = .systemFont(ofSize: 12)
        balance.textColor = .secondaryLabelColor
        let balanceGroup = NSStackView(views: [summaryLabel, balance])
        balanceGroup.alignment = .firstBaseline
        balanceGroup.spacing = 5
        let dates = verticalStack([resetCountdownLabel, resetDateLabel], spacing: 4)
        let header = row(balanceGroup, dates)
        header.heightAnchor.constraint(equalToConstant: 44).isActive = true

        let progressSection = verticalStack([timeProgressRow, quotaProgressRow, forecastLabel], spacing: 6)
        forecastLabel.toolTip = "按本周期平均消耗速度估算，仅供参考。周期初期样本较少，预计时间可能大幅波动。"
        let detailStack = verticalStack([
            row(subscriptionCaption, subscriptionLabel),
            row(creditCaption, resetCreditLabel),
            row(automaticResetCheckbox, useButton)
        ], spacing: 8)

        let secondaryActions = NSStackView(views: [refreshButton, moreButton])
        secondaryActions.orientation = .horizontal
        secondaryActions.alignment = .centerY
        secondaryActions.spacing = 6

        let footerText = NSStackView(views: [freshnessLabel, publicResetInfoLabel])
        footerText.spacing = 4
        let actionRow = row(footerText, secondaryActions)

        let stack = verticalStack([
            header, progressSection, separator(), detailStack, separator(),
            publicResetSection, separator(), actionRow
        ], spacing: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
        ])

        view = root
        preferredContentSize = NSSize(width: 360, height: 350)
    }

    private func verticalStack(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        for view in views { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        return stack
    }

    private func row(_ left: NSView, _ right: NSView) -> NSStackView {
        let stack = NSStackView(views: [left, NSView(), right])
        stack.alignment = .centerY
        stack.spacing = 8
        return stack
    }

    private func separator() -> NSBox {
        let line = NSBox()
        line.boxType = .separator
        return line
    }

    @objc private func showMoreMenu() {
        moreButton.menu?.popUp(positioning: nil, at: NSPoint(x: 0, y: moreButton.bounds.maxY), in: moreButton)
    }

    func updateAutomaticReset(enabled: Bool, available: Bool) {
        automaticResetCheckbox.state = enabled ? .on : .off
        automaticResetCheckbox.isEnabled = available
    }

    func showLoading(previousStatus: QuotaStatus?) {
        refreshButton.isEnabled = false
        useButton.isEnabled = false
        automaticResetCheckbox.isEnabled = false
        freshnessLabel.stringValue = previousStatus == nil ? "正在连接 Codex…" : "正在刷新…"
    }

    func update(status: QuotaStatus, timeZone: TimeZone = .autoupdatingCurrent) {
        currentStatus = status
        updateDateText(status: status, timeZone: timeZone)

        let actionState = QuotaDisplayFormatter.resetCreditActionState(
            availableCount: status.accountFingerprint == nil
                ? nil
                : status.resetCreditsAvailableCount
        )
        useButton.title = actionState.isEnabled ? "使用重置券…" : actionState.title
        useButton.isEnabled = actionState.isEnabled
        refreshButton.isEnabled = true
        freshnessLabel.stringValue = QuotaDisplayFormatter.freshnessText(for: status)
    }

    private func updateDateText(status: QuotaStatus, timeZone: TimeZone) {
        let title = QuotaDisplayFormatter.hoverTitle(for: status, timeZone: timeZone).components(separatedBy: " · ")
        summaryLabel.stringValue = title[0]
        summaryLabel.toolTip = QuotaDisplayFormatter.tooltip(for: status, timeZone: timeZone)
        resetDateLabel.stringValue = title.count > 1 ? title[1] : "重置时间暂不可用"
        resetCountdownLabel.stringValue = title.count > 2 ? "\(title[2])后重置" : ""
        let subscription = QuotaDisplayFormatter.subscriptionExpirationText(
            for: status,
            timeZone: timeZone
        )
        let subscriptionParts = subscription.components(separatedBy: "：")
        subscriptionCaption.stringValue = subscriptionParts[0]
        subscriptionLabel.stringValue = subscriptionParts.dropFirst().joined(separator: "：")
        subscriptionLabel.toolTip = subscription
        let credit = QuotaDisplayFormatter.resetCreditDetailText(
            for: status,
            timeZone: timeZone
        )
        creditCaption.stringValue = status.resetCreditsAvailableCount.map { "重置券 \($0)张" } ?? "重置券"
        resetCreditLabel.stringValue = status.nearestResetCreditExpiresAt != nil
            ? "最早 " + credit.components(separatedBy: "：").dropFirst().joined(separator: "：")
            : (status.resetCreditsAvailableCount == 0 ? "暂无" : "到期时间暂不可用")
        resetCreditLabel.toolTip = credit
        updateProgress(QuotaCycleProgress.calculate(for: status))
        forecastLabel.stringValue = QuotaDisplayFormatter.exhaustionForecastText(
            for: status,
            timeZone: timeZone
        ).replacingOccurrences(of: "按周期均速，预计", with: "均速预计")

    }

    func updatePublicReset(_ status: PublicResetStatus?, failed: Bool,
                           timeZone: TimeZone = .autoupdatingCurrent) {
        publicResetStatus = status
        publicResetFailed = failed
        let presentation = status?.presentation(timeZone: timeZone)
        publicResetLabel.stringValue = presentation?.title ?? (failed ? "Tibo 重置：暂不可用" : "Tibo 重置：读取中…")
        publicResetLatestLabel.stringValue = presentation?.latest ?? "最近公告：尚未读取"
        let state = failed ? (status == nil ? "公告连接失败" : "刷新失败，显示上次公告") : "第三方公告追踪"
        publicResetInfoLabel.stringValue = "· 本机时间"
        publicResetWarningLabel.stringValue = failed ? state : ""
        publicResetWarningLabel.isHidden = !failed
        preferredContentSize.height = failed ? 370 : 350
        for label in [publicResetLabel, publicResetLatestLabel, publicResetInfoLabel] {
            label.toolTip = "\(state)\n" + (presentation?.detail ?? "本机时区：\(timeZone.identifier)\nCodex Resets · 第三方公告追踪")
        }
        publicResetSourceURL = presentation?.sourceURL
        publicResetSourceButton.isEnabled = publicResetSourceURL != nil
    }

    func refreshTimeZone(_ timeZone: TimeZone = .autoupdatingCurrent) {
        // Reformat only: an in-flight account refresh/redemption must keep its controls disabled.
        if let currentStatus { updateDateText(status: currentStatus, timeZone: timeZone) }
        updatePublicReset(publicResetStatus, failed: publicResetFailed, timeZone: timeZone)
    }

    @objc private func openPublicResetSource() {
        guard let publicResetSourceURL else { return }
        NSWorkspace.shared.open(publicResetSourceURL)
    }

    func showError(hasCachedStatus: Bool) {
        refreshButton.isEnabled = true
        if hasCachedStatus {
            freshnessLabel.stringValue = "刷新失败，当前显示上次结果"
        } else {
            summaryLabel.stringValue = "--"
            resetCountdownLabel.stringValue = "读取失败"
            resetDateLabel.stringValue = "重置时间暂不可用"
            subscriptionLabel.stringValue = "暂不可用"
            resetCreditLabel.stringValue = "暂不可用"
            updateProgress(nil)
            forecastLabel.stringValue = "按周期均速，暂无法估算"
            freshnessLabel.stringValue = "请确认 Codex 已登录后重试"
            useButton.title = "重置券暂不可用"
            useButton.isEnabled = false
        }
    }

    func setConsuming(_ consuming: Bool) {
        automaticResetCheckbox.isEnabled = !consuming && currentStatus?.accountFingerprint != nil
        let actionState = QuotaDisplayFormatter.resetCreditActionState(
            availableCount: currentStatus?.accountFingerprint == nil
                ? nil
                : currentStatus?.resetCreditsAvailableCount
        )
        useButton.isEnabled = !consuming && actionState.isEnabled
        useButton.title = consuming ? "正在重置…" : (actionState.isEnabled ? "使用重置券…" : actionState.title)
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

    @objc private func automaticResetChanged() {
        onAutomaticResetChanged?(automaticResetCheckbox.state == .on)
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
    private let progressIndicator = QuotaProgressTrack()
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

        progressIndicator.fillColor = accessibilityLabel == "时间已过" ? .secondaryLabelColor : .controlAccentColor
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
            titleLabel.widthAnchor.constraint(equalToConstant: 48),
            progressIndicator.heightAnchor.constraint(equalToConstant: 8),
            progressIndicator.widthAnchor.constraint(greaterThanOrEqualToConstant: 150),
            percentLabel.widthAnchor.constraint(equalToConstant: 34),
            heightAnchor.constraint(equalToConstant: 18),
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
        progressIndicator.setAccessibilityRole(.progressIndicator)
        progressIndicator.setAccessibilityLabel(progressAccessibilityLabel)
        progressIndicator.setAccessibilityValue("\(percent)%")
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

private final class QuotaProgressTrack: NSView {
    var doubleValue: Double = 0 { didSet { needsDisplay = true } }
    var fillColor: NSColor = .controlAccentColor

    override func draw(_ dirtyRect: NSRect) {
        let track = NSRect(x: 0, y: (bounds.height - 5) / 2, width: bounds.width, height: 5)
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: track, xRadius: 2.5, yRadius: 2.5).fill()
        let fraction = min(1, max(0, doubleValue))
        guard fraction > 0 else { return }
        fillColor.setFill()
        let fill = NSRect(x: track.minX, y: track.minY, width: track.width * fraction, height: track.height)
        NSBezierPath(roundedRect: fill, xRadius: min(2.5, fill.width / 2), yRadius: 2.5).fill()
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
