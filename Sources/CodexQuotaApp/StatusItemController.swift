import AppKit
import CodexQuotaCore

@MainActor
final class QuotaOverlayController: NSObject, NSPopoverDelegate {
    private static let pendingResetRequestsDefaultsKey =
        "com.mufeng.codexquota.pending-reset-requests-v2"
    private static let legacyPendingResetKeyDefaultsKey =
        "com.mufeng.codexquota.pending-reset-idempotency-key"

    private let service = QuotaService()
    private let overlayPanel = QuotaOverlayPanel()
    private let popover = NSPopover()
    private let popoverController = QuotaPopoverViewController()
    private let sidebarLocator = CodexSidebarLocator()

    private var placementTimer: Timer?
    private var refreshTimer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var currentStatus: QuotaStatus?
    private var isConsuming = false
    private var isConfirmingReset = false
    private var interactionKeepsVisible = false
    private var pendingResetRequests: [String: PendingResetCreditRequest] = [:]
    private var isPointerOverChip = false
    private var isPointerOverPopover = false
    private var closePopoverWorkItem: DispatchWorkItem?
    private var targetApplication: NSRunningApplication?
    private var isShowingAccessibilityPrompt = false
    private var lastKnownSidebarTrailingX: CGFloat?
    private var lastKnownFooterCenterBottomInset: CGFloat?
    private var lastKnownTrailingControlMinX: CGFloat?
    private var standardChipTitle = "-- · 读取中"
    private var standardChipTooltip = "正在读取 Codex 额度"
    private var standardChipDeviation: QuotaUsageDeviation?

    override init() {
        super.init()

        if let data = UserDefaults.standard.data(
            forKey: Self.pendingResetRequestsDefaultsKey
        ), let stored = try? JSONDecoder().decode(
            [String: PendingResetCreditRequest].self,
            from: data
        ) {
            pendingResetRequests = stored
        }
        UserDefaults.standard.removeObject(
            forKey: Self.legacyPendingResetKeyDefaultsKey
        )

        configurePopover()
        configureActions()
        observeWorkspace()
        schedulePlacementUpdates()
        scheduleRefresh()
        updateOverlayPlacement()
        refresh(forceTokenRefresh: true)
    }

    deinit {
        placementTimer?.invalidate()
        refreshTimer?.invalidate()
        refreshTask?.cancel()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    private func configurePopover() {
        _ = popoverController.view
        popover.contentViewController = popoverController
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
    }

    private func configureActions() {
        overlayPanel.chipView.onActivate = { [weak self] in
            guard let self else { return }
            if isShowingAccessibilityPrompt {
                openAccessibilitySettings()
            } else {
                showPopover()
            }
        }
        overlayPanel.chipView.onHoverChanged = { [weak self] isInside in
            guard let self else { return }
            guard !isShowingAccessibilityPrompt else {
                cancelScheduledPopoverClose()
                return
            }
            isPointerOverChip = isInside
            if isInside {
                cancelScheduledPopoverClose()
                showPopover()
            } else {
                schedulePopoverClose()
            }
        }
        popoverController.onRefresh = { [weak self] in
            self?.refresh(forceTokenRefresh: true)
        }
        popoverController.onUseResetCredit = { [weak self] in
            self?.confirmAndConsumeResetCredit()
        }
        popoverController.onQuit = { [weak self] in
            self?.confirmAndQuit()
        }
        popoverController.onHoverChanged = { [weak self] isInside in
            guard let self else { return }
            isPointerOverPopover = isInside
            if isInside {
                cancelScheduledPopoverClose()
            } else {
                schedulePopoverClose()
            }
        }
    }

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
        ] {
            center.addObserver(
                self,
                selector: #selector(workspaceStateChanged(_:)),
                name: name,
                object: nil
            )
        }
    }

    private func schedulePlacementUpdates() {
        let timer = Timer(
            timeInterval: 0.25,
            target: self,
            selector: #selector(placementTimerFired),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        placementTimer = timer
    }

    private func scheduleRefresh() {
        let timer = Timer(
            timeInterval: 300,
            target: self,
            selector: #selector(refreshTimerFired),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    @objc private func workspaceStateChanged(_ notification: Notification) {
        if notification.name == NSWorkspace.didLaunchApplicationNotification,
           let application = notification.userInfo?[
               NSWorkspace.applicationUserInfoKey
           ] as? NSRunningApplication,
           application.bundleIdentifier == CodexWindowLocator.bundleIdentifier {
            refresh(forceTokenRefresh: true)
        }
        updateOverlayPlacement()
    }

    @objc private func placementTimerFired() {
        updateOverlayPlacement()
    }

    @objc private func refreshTimerFired() {
        refresh(forceTokenRefresh: false)
    }

    private func updateOverlayPlacement() {
        let frontmostBundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let helperBundleIdentifier = Bundle.main.bundleIdentifier
        let isCodexFrontmost = frontmostBundleIdentifier == CodexWindowLocator.bundleIdentifier
        let isInteractingWithHelper = frontmostBundleIdentifier == helperBundleIdentifier
            && (popover.isShown || interactionKeepsVisible || isConsuming)

        guard isCodexFrontmost || isInteractingWithHelper,
              let targetWindow = CodexWindowLocator.locateMainWindow() else {
            hideOverlay()
            return
        }

        targetApplication = targetWindow.application
        let sidebarTrailingX: CGFloat?
        switch sidebarLocator.placement(for: targetWindow) {
        case .permissionRequired:
            showAccessibilityPrompt(for: targetWindow)
            return
        case .unavailable:
            restoreStandardChipIfNeeded()
            hideOverlay()
            return
        case .hidden:
            restoreStandardChipIfNeeded()
            lastKnownFooterCenterBottomInset = nil
            lastKnownTrailingControlMinX = nil
            hideOverlay()
            return
        case let .visible(
            trailingEdgeX,
            footerCenterBottomInset,
            trailingControlMinX
        ):
            restoreStandardChipIfNeeded()
            lastKnownSidebarTrailingX = trailingEdgeX
            lastKnownFooterCenterBottomInset = footerCenterBottomInset
            lastKnownTrailingControlMinX = trailingControlMinX
            sidebarTrailingX = trailingEdgeX
        }
        let frame = CodexOverlayGeometry.badgeFrame(
            for: targetWindow.frame,
            sidebarTrailingX: sidebarTrailingX,
            footerCenterBottomInset: lastKnownFooterCenterBottomInset,
            trailingControlMinX: lastKnownTrailingControlMinX
        )
        if overlayPanel.frame != frame {
            overlayPanel.setFrame(frame, display: true)
        }

        if !overlayPanel.isVisible {
            overlayPanel.orderFrontRegardless()
        }
    }

    private func hideOverlay() {
        if popover.isShown {
            popover.performClose(nil)
        }
        overlayPanel.orderOut(nil)
    }

    private func showAccessibilityPrompt(for targetWindow: LocatedCodexWindow) {
        if popover.isShown {
            popover.performClose(nil)
        }
        if !isShowingAccessibilityPrompt {
            isShowingAccessibilityPrompt = true
            overlayPanel.chipView.setNeedsAttention(true)
            overlayPanel.chipView.update(
                title: "请开启辅助功能",
                tooltip: "点击打开系统设置，授权后将自动恢复 Codex 额度",
                usageDeviation: nil
            )
        }

        let fallbackTrailingX = lastKnownSidebarTrailingX
            ?? min(targetWindow.frame.minX + 336, targetWindow.frame.maxX - 100)
        let frame = CodexOverlayGeometry.badgeFrame(
            for: targetWindow.frame,
            sidebarTrailingX: fallbackTrailingX,
            footerCenterBottomInset: lastKnownFooterCenterBottomInset,
            trailingControlMinX: lastKnownTrailingControlMinX
        )
        if overlayPanel.frame != frame {
            overlayPanel.setFrame(frame, display: true)
        }
        if !overlayPanel.isVisible {
            overlayPanel.orderFrontRegardless()
        }
    }

    private func restoreStandardChipIfNeeded() {
        guard isShowingAccessibilityPrompt else { return }
        isShowingAccessibilityPrompt = false
        overlayPanel.chipView.setNeedsAttention(false)

        overlayPanel.chipView.update(
            title: standardChipTitle,
            tooltip: standardChipTooltip,
            usageDeviation: standardChipDeviation
        )
    }

    private func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security"
                + "?Privacy_Accessibility"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func refresh(forceTokenRefresh: Bool) {
        guard refreshTask == nil, !isConsuming, !isConfirmingReset else { return }

        popoverController.showLoading(previousStatus: currentStatus)
        refreshTask = Task { [weak self] in
            guard let self else { return }
            defer { refreshTask = nil }

            do {
                let status = try await service.fetch(
                    forceTokenRefresh: forceTokenRefresh
                )
                guard !Task.isCancelled else { return }

                currentStatus = status
                updateDisplay(with: status)
            } catch {
                guard !Task.isCancelled else { return }
                showRefreshError()
            }
        }
    }

    private func updateDisplay(with status: QuotaStatus) {
        let title = QuotaDisplayFormatter.mainTitle(for: status, timeZone: .current)
        let tooltip = QuotaDisplayFormatter.tooltip(for: status, timeZone: .current)
        let deviation = QuotaCycleProgress.calculate(for: status)?.usageDeviation
        standardChipTitle = title
        standardChipTooltip = tooltip
        standardChipDeviation = deviation
        if !isShowingAccessibilityPrompt {
            overlayPanel.chipView.update(
                title: title,
                tooltip: tooltip,
                usageDeviation: deviation
            )
        }
        popoverController.update(status: status, timeZone: .current)
    }

    private func showRefreshError() {
        popoverController.showError(hasCachedStatus: currentStatus != nil)
        guard currentStatus == nil else { return }
        standardChipTitle = "-- · 读取失败"
        standardChipTooltip = "Codex 额度读取失败；点击后可重试"
        standardChipDeviation = nil
        if !isShowingAccessibilityPrompt {
            overlayPanel.chipView.update(
                title: standardChipTitle,
                tooltip: standardChipTooltip,
                usageDeviation: nil
            )
        }
    }

    private func showPopover() {
        guard overlayPanel.isVisible, !isShowingAccessibilityPrompt else { return }
        cancelScheduledPopoverClose()
        overlayPanel.chipView.setExpanded(true)

        guard !popover.isShown else { return }
        popover.show(
            relativeTo: overlayPanel.chipView.bounds,
            of: overlayPanel.chipView,
            preferredEdge: .maxY
        )
    }

    func popoverDidClose(_ notification: Notification) {
        cancelScheduledPopoverClose()
        isPointerOverPopover = false
        overlayPanel.chipView.setExpanded(false)
        updateOverlayPlacement()
    }

    private func schedulePopoverClose() {
        closePopoverWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  !isPointerOverChip,
                  !isPointerOverPopover,
                  !isConsuming else { return }
            popover.performClose(nil)
        }
        closePopoverWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    private func cancelScheduledPopoverClose() {
        closePopoverWorkItem?.cancel()
        closePopoverWorkItem = nil
    }

    private func confirmAndConsumeResetCredit() {
        guard !isConsuming,
              !isConfirmingReset,
              refreshTask == nil,
              (currentStatus?.resetCreditsAvailableCount ?? 0) > 0,
              let accountFingerprint = currentStatus?.accountFingerprint else {
            return
        }

        isConfirmingReset = true
        interactionKeepsVisible = true
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "使用 1 张额度重置券？"
        alert.informativeText = "这会立即重置当前可用的 Codex 额度，且无法撤销。系统会使用一张可用重置券。"
        alert.addButton(withTitle: "确认使用")
        alert.addButton(withTitle: "取消")

        let response = alert.runModal()
        isConfirmingReset = false
        interactionKeepsVisible = false
        targetApplication?.activate(options: [.activateIgnoringOtherApps])
        updateOverlayPlacement()

        guard response == .alertFirstButtonReturn else { return }
        consumeResetCredit(expectedAccountFingerprint: accountFingerprint)
    }

    private func confirmAndQuit() {
        interactionKeepsVisible = true
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "退出 Codex 昵称额度？"
        alert.informativeText = "退出后额度将停止显示；下次登录时会自动启动。"
        alert.addButton(withTitle: "退出")
        alert.addButton(withTitle: "取消")

        let response = alert.runModal()
        interactionKeepsVisible = false

        if response == .alertFirstButtonReturn {
            NSApplication.shared.terminate(nil)
        } else {
            targetApplication?.activate(options: [.activateIgnoringOtherApps])
            updateOverlayPlacement()
        }
    }

    private func consumeResetCredit(expectedAccountFingerprint: String) {
        guard !isConsuming, refreshTask == nil else { return }

        isConsuming = true
        popoverController.setConsuming(true)

        let pendingRequest = pendingResetRequest(
            for: expectedAccountFingerprint,
            now: Date()
        )
        let idempotencyKey = pendingRequest.idempotencyKey

        Task { [weak self] in
            guard let self else { return }

            do {
                let result = try await service.consumeResetCredit(
                    expectedAccountFingerprint: expectedAccountFingerprint,
                    idempotencyKey: idempotencyKey
                )
                isConsuming = false
                removePendingResetRequest(for: expectedAccountFingerprint)
                popoverController.setConsuming(false)

                switch result {
                case .reset, .alreadyRedeemed:
                    refresh(forceTokenRefresh: false)
                    showPopover()
                    popoverController.showActionMessage("额度已重置，正在更新…")
                case .nothingToReset:
                    showPopover()
                    popoverController.showActionMessage("当前额度无需重置，重置券未消耗")
                case .noCredit:
                    refresh(forceTokenRefresh: false)
                    showPopover()
                    popoverController.showActionMessage("当前没有可用重置券")
                }
            } catch {
                isConsuming = false
                popoverController.setConsuming(false)
                showPopover()
                if (error as? QuotaServiceError) == .accountChanged {
                    removePendingResetRequest(for: expectedAccountFingerprint)
                    popoverController.showActionMessage(
                        "账户已切换，未使用重置券；正在刷新…"
                    )
                    refresh(forceTokenRefresh: true)
                } else {
                    popoverController.showActionMessage(
                        "使用失败；24 小时内重试会沿用同一请求"
                    )
                }
            }
        }
    }

    private func pendingResetRequest(
        for accountFingerprint: String,
        now: Date
    ) -> PendingResetCreditRequest {
        if let existing = pendingResetRequests[accountFingerprint],
           existing.isReusable(for: accountFingerprint, now: now) {
            return existing
        }

        let request = PendingResetCreditRequest(
            accountFingerprint: accountFingerprint,
            idempotencyKey: UUID(),
            createdAt: now
        )
        pendingResetRequests[accountFingerprint] = request
        persistPendingResetRequests()
        return request
    }

    private func removePendingResetRequest(for accountFingerprint: String) {
        pendingResetRequests.removeValue(forKey: accountFingerprint)
        persistPendingResetRequests()
    }

    private func persistPendingResetRequests() {
        guard !pendingResetRequests.isEmpty else {
            UserDefaults.standard.removeObject(
                forKey: Self.pendingResetRequestsDefaultsKey
            )
            return
        }
        guard let data = try? JSONEncoder().encode(pendingResetRequests) else {
            return
        }
        UserDefaults.standard.set(
            data,
            forKey: Self.pendingResetRequestsDefaultsKey
        )
    }
}
