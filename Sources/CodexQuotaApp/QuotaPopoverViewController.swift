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
    private let resetDateLabel = NSTextField(labelWithString: L("重置时间读取中", "Loading reset time"))
    private let resetCountdownLabel = NSTextField(labelWithString: L("--天后重置", "Reset in --d"))
    private let subscriptionCaption = NSTextField(labelWithString: L("会员到期", "Membership expires"))
    private let creditCaption = NSTextField(labelWithString: L("重置券", "Reset credits"))
    private let timeProgressRow = QuotaProgressRowView(
        title: L("时间已过", "Elapsed"),
        accessibilityLabel: L("时间已过", "Elapsed")
    )
    private let quotaProgressRow = QuotaProgressRowView(
        title: L("额度已用", "Used"),
        accessibilityLabel: L("额度已用", "Used")
    )
    private let forecastLabel = NSTextField(labelWithString: L("按周期均速，暂无法估算", "Not enough data to estimate"))
    private let subscriptionLabel = NSTextField(labelWithString: L("会员到期：读取中", "Membership expires: loading"))
    private let resetCreditLabel = NSTextField(labelWithString: L("最早到期券：读取中", "Earliest credit: loading"))
    private let freshnessLabel = NSTextField(labelWithString: L("正在连接 Codex…", "Connecting to Codex…"))
    private let publicResetLabel = NSTextField(wrappingLabelWithString: L("Tibo 重置：读取中…", "Tibo reset: loading…"))
    private let publicResetLatestLabel = NSTextField(wrappingLabelWithString: L("最近公告：读取中…", "Latest notice: loading…"))
    private let publicResetConfidenceLabel = NSTextField(wrappingLabelWithString: "")
    private let publicResetInfoLabel = NSTextField(labelWithString: L("· 本机时间", "· Local time"))
    private let publicResetWarningLabel = NSTextField(labelWithString: "")
    private let publicResetSourceButton = NSButton(title: L("查看来源", "View source"), target: nil, action: nil)
    private let automaticResetCheckbox = NSButton(
        checkboxWithTitle: L("临期自动使用重置券", "Auto-use expiring credits"), target: nil, action: nil
    )
    private let useButton = NSButton(title: L("使用重置券", "Use reset credit"), target: nil, action: nil)
    private let refreshButton = NSButton(title: L("刷新", "Refresh"), target: nil, action: nil)
    private let moreButton = NSButton(title: L("更多", "More"), target: nil, action: nil)

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

        for label in [publicResetLabel, publicResetLatestLabel, publicResetConfidenceLabel, publicResetInfoLabel, publicResetWarningLabel] {
            label.font = .systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
            label.maximumNumberOfLines = 2
            label.lineBreakMode = .byTruncatingTail
        }
        publicResetLabel.font = .systemFont(ofSize: 12)
        publicResetLabel.textColor = .labelColor
        publicResetInfoLabel.toolTip = L("本机时区：\(TimeZone.autoupdatingCurrent.identifier)\nCodex Resets · 第三方公告追踪", "Local time zone: \(TimeZone.autoupdatingCurrent.identifier)\nCodex Resets · Third-party announcement tracker")
        publicResetInfoLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        publicResetWarningLabel.isHidden = true
        publicResetConfidenceLabel.isHidden = true
        publicResetSourceButton.bezelStyle = .inline
        publicResetSourceButton.controlSize = .small
        publicResetSourceButton.isEnabled = false
        publicResetSourceButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        publicResetSourceButton.target = self
        publicResetSourceButton.action = #selector(openPublicResetSource)
        let publicResetSection = verticalStack([
            publicResetLabel, publicResetConfidenceLabel,
            row(publicResetLatestLabel, publicResetSourceButton), publicResetWarningLabel
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
        let quitItem = NSMenuItem(title: L("退出…", "Quit…"), action: #selector(quit), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)
        moreButton.menu = menu
        for (button, symbol, help) in [
            (refreshButton, "arrow.clockwise", L("刷新额度与公共公告", "Refresh quota and public notices")),
            (moreButton, "ellipsis", L("更多操作", "More actions")),
            (publicResetSourceButton, "arrow.up.right", L("查看公告来源", "View announcement source"))
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
        automaticResetCheckbox.toolTip = L("仅对此账户生效：最早到期券进入最后 30 分钟时自动尝试使用 1 张。需要应用运行且电脑保持唤醒联网。", "For this account only: try to use one credit during its final 30 minutes. The app must be running and the computer awake and online.")

        let balance = NSTextField(labelWithString: L("剩余", "remaining"))
        balance.font = .systemFont(ofSize: 12)
        balance.textColor = .secondaryLabelColor
        let balanceGroup = NSStackView(views: [summaryLabel, balance])
        balanceGroup.alignment = .firstBaseline
        balanceGroup.spacing = 5
        let dates = verticalStack([resetCountdownLabel, resetDateLabel], spacing: 4)
        let header = row(balanceGroup, dates)
        header.heightAnchor.constraint(equalToConstant: 44).isActive = true

        let progressSection = verticalStack([quotaProgressRow, timeProgressRow, forecastLabel], spacing: 6)
        forecastLabel.toolTip = L("按本周期平均消耗速度估算，仅供参考。周期初期样本较少，预计时间可能大幅波动。", "Estimated from average usage this cycle, not a guarantee. Estimates can vary widely early in the cycle.")
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
        freshnessLabel.stringValue = previousStatus == nil ? L("正在连接 Codex…", "Connecting to Codex…") : L("正在刷新…", "Refreshing…")
    }

    func update(status: QuotaStatus, timeZone: TimeZone = .autoupdatingCurrent) {
        currentStatus = status
        updateDateText(status: status, timeZone: timeZone)

        let actionState = QuotaDisplayFormatter.resetCreditActionState(
            availableCount: status.accountFingerprint == nil
                ? nil
                : status.resetCreditsAvailableCount
        )
        useButton.title = actionState.isEnabled ? L("使用重置券…", "Use reset credit…") : actionState.title
        useButton.isEnabled = actionState.isEnabled
        refreshButton.isEnabled = true
        freshnessLabel.stringValue = QuotaDisplayFormatter.freshnessText(for: status)
    }

    private func updateDateText(status: QuotaStatus, timeZone: TimeZone) {
        let title = QuotaDisplayFormatter.hoverTitle(for: status, timeZone: timeZone).components(separatedBy: " · ")
        summaryLabel.stringValue = title[0]
        summaryLabel.toolTip = QuotaDisplayFormatter.tooltip(for: status, timeZone: timeZone)
        resetDateLabel.stringValue = title.count > 1 ? title[1] : L("重置时间暂不可用", "Reset time unavailable")
        resetCountdownLabel.stringValue = title.count > 2 ? L("\(title[2])后重置", "Reset in \(title[2])") : ""
        let subscription = QuotaDisplayFormatter.subscriptionExpirationText(
            for: status,
            timeZone: timeZone
        )
        let subscriptionParts = subscription.components(separatedBy: L("：", ": "))
        subscriptionCaption.stringValue = subscriptionParts[0]
        subscriptionLabel.stringValue = subscriptionParts.dropFirst().joined(separator: L("：", ": "))
        subscriptionLabel.toolTip = subscription
        let credit = QuotaDisplayFormatter.resetCreditDetailText(
            for: status,
            timeZone: timeZone
        )
        creditCaption.stringValue = status.resetCreditsAvailableCount.map { L("重置券 \($0)张", "Reset credits (\($0))") } ?? L("重置券", "Reset credits")
        resetCreditLabel.stringValue = status.nearestResetCreditExpiresAt != nil
            ? L("最早 ", "Earliest ") + credit.components(separatedBy: L("：", ": ")).dropFirst().joined(separator: L("：", ": "))
            : (status.resetCreditsAvailableCount == 0 ? L("暂无", "None") : L("到期时间暂不可用", "Expiry unavailable"))
        resetCreditLabel.toolTip = credit
        forecastLabel.stringValue = QuotaDisplayFormatter.exhaustionForecastText(
            for: status,
            timeZone: timeZone
        ).replacingOccurrences(of: L("按周期均速，预计", "At this pace, runs out"), with: L("均速预计", "Est. runs out"))
        updateProgress(QuotaCycleProgress.calculate(for: status))

    }

    func updatePublicReset(_ status: PublicResetStatus?, failed: Bool,
                           timeZone: TimeZone = .autoupdatingCurrent) {
        publicResetStatus = status
        publicResetFailed = failed
        let presentation = status?.presentation(timeZone: timeZone)
        publicResetLabel.stringValue = presentation?.title ?? (failed ? L("Tibo 重置：暂不可用", "Tibo reset: unavailable") : L("Tibo 重置：读取中…", "Tibo reset: loading…"))
        publicResetLatestLabel.stringValue = presentation?.latest ?? L("最近公告：尚未读取", "Latest notice: not loaded")
        publicResetConfidenceLabel.stringValue = presentation?.confidence ?? ""
        publicResetConfidenceLabel.isHidden = presentation?.confidence == nil
        let state = failed ? (status == nil ? L("公告连接失败", "Could not load notices") : L("刷新失败，显示上次公告", "Refresh failed; showing cached notice")) : L("第三方公告追踪", "Third-party announcement tracker")
        publicResetInfoLabel.stringValue = L("· 本机时间", "· Local time")
        publicResetWarningLabel.stringValue = failed ? state : ""
        publicResetWarningLabel.isHidden = !failed
        preferredContentSize.height = (failed ? 370 : 350) + (presentation?.confidence == nil ? 0 : 24)
        for label in [publicResetLabel, publicResetLatestLabel, publicResetConfidenceLabel, publicResetInfoLabel] {
            label.toolTip = "\(state)\n" + (presentation?.detail ?? L("本机时区：\(timeZone.identifier)\nCodex Resets · 第三方公告追踪", "Local time zone: \(timeZone.identifier)\nCodex Resets · Third-party announcement tracker"))
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
            freshnessLabel.stringValue = L("刷新失败，当前显示上次结果", "Refresh failed; showing cached data")
        } else {
            summaryLabel.stringValue = "--"
            resetCountdownLabel.stringValue = L("读取失败", "Could not load")
            resetDateLabel.stringValue = L("重置时间暂不可用", "Reset time unavailable")
            subscriptionLabel.stringValue = L("暂不可用", "Unavailable")
            resetCreditLabel.stringValue = L("暂不可用", "Unavailable")
            updateProgress(nil)
            forecastLabel.stringValue = L("按周期均速，暂无法估算", "Not enough data to estimate")
            freshnessLabel.stringValue = L("请确认 Codex 已登录后重试", "Sign in to Codex and try again")
            useButton.title = L("重置券暂不可用", "Credits unavailable")
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
        useButton.title = consuming ? L("正在重置…", "Resetting…") : (actionState.isEnabled ? L("使用重置券…", "Use reset credit…") : actionState.title)
        refreshButton.isEnabled = !consuming
        freshnessLabel.stringValue = consuming ? L("正在安全使用 1 张重置券…", "Safely using one reset credit…") : freshnessLabel.stringValue
    }

    func showActionMessage(_ message: String) {
        freshnessLabel.stringValue = message
    }

    private func updateProgress(_ progress: QuotaCycleProgress?) {
        timeProgressRow.update(
            fraction: progress?.timeElapsedFraction,
            percent: progress?.timeElapsedPercent,
            markerFraction: progress?.exhaustionTimeFraction,
            markerHelp: L("竖线为预计用完点 · \(forecastLabel.stringValue)\n按本周期均速估算，仅供参考。", "Marker: \(forecastLabel.stringValue)\nEstimated from average usage this cycle, not a guarantee.")
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

        progressIndicator.fillColor = accessibilityLabel == L("时间已过", "Elapsed") ? .secondaryLabelColor : .controlAccentColor
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
            progressIndicator.heightAnchor.constraint(equalToConstant: 12),
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

    func update(fraction: Double?, percent: Int?, markerFraction: Double? = nil, markerHelp: String? = nil) {
        guard let fraction, let percent else {
            setUnavailable()
            return
        }

        progressIndicator.doubleValue = fraction
        progressIndicator.markerFraction = markerFraction
        progressIndicator.toolTip = markerFraction == nil ? nil : markerHelp
        progressIndicator.setAccessibilityHelp(markerFraction == nil ? nil : markerHelp)
        percentLabel.stringValue = "\(percent)%"
        setAccessibilityElement(false)
        progressIndicator.setAccessibilityElement(true)
        progressIndicator.setAccessibilityRole(.progressIndicator)
        progressIndicator.setAccessibilityLabel(progressAccessibilityLabel)
        progressIndicator.setAccessibilityValue("\(percent)%")
    }

    private func setUnavailable() {
        progressIndicator.doubleValue = 0
        progressIndicator.markerFraction = nil
        progressIndicator.toolTip = nil
        progressIndicator.setAccessibilityHelp(nil)
        percentLabel.stringValue = "--"
        progressIndicator.setAccessibilityElement(false)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(L("\(progressAccessibilityLabel)：暂不可用", "\(progressAccessibilityLabel): unavailable"))
    }
}

private final class QuotaProgressTrack: NSView {
    var doubleValue: Double = 0 { didSet { needsDisplay = true } }
    var fillColor: NSColor = .controlAccentColor
    private let marker = NSBox()
    var markerFraction: Double? {
        didSet {
            marker.isHidden = markerFraction == nil
            if markerFraction != oldValue { needsLayout = true }
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        marker.boxType = .custom
        marker.borderWidth = 0
        marker.fillColor = .secondaryLabelColor
        marker.cornerRadius = 0.5
        marker.identifier = NSUserInterfaceItemIdentifier("exhaustion-marker")
        marker.isHidden = true
        marker.setAccessibilityElement(false)
        addSubview(marker)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        guard let markerFraction else { return }
        let width: CGFloat = 2
        let x = min(max(0, bounds.width * markerFraction - width / 2), max(0, bounds.width - width))
        marker.frame = NSRect(x: x, y: 0, width: width, height: bounds.height)
    }

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
        super.updateTrackingAreas()
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
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
    }
}
