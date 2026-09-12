import AppKit
import CodexQuotaCore

private struct CheckFailure: Error { let message: String }

private final class FakePublicResetService: PublicResetServicing {
    var fetchCount = 0
    var fails = false
    func fetch() async throws -> PublicResetStatus {
        fetchCount += 1
        if fails { throw PublicResetError.unavailable }
        return try PublicResetStatus.parse(PublicResetHTTPTests.fixture)
    }
}

private final class FakeQuotaService: QuotaServicing {
    var account = "demo-account-a"
    var expiresAt = Date().addingTimeInterval(1_700)
    var fetchFails = false
    var consumeFails = false
    var consumeRequests: [UUID] = []
    var fetchCount = 0

    func fetch(forceTokenRefresh: Bool) async throws -> QuotaStatus {
        fetchCount += 1
        if fetchFails { throw QuotaServiceError.appServerTimedOut }
        return QuotaStatus(
            remainingPercent: 40, resetsAt: Date().addingTimeInterval(86_400),
            windowDurationMins: 10_080, planType: "pro", subscriptionActiveUntil: nil,
            resetCreditsAvailableCount: 1, nearestResetCreditExpiresAt: expiresAt,
            fetchedAt: Date(), warnings: [], accountFingerprint: account
        )
    }

    func consumeResetCredit(expectedAccountFingerprint: String, idempotencyKey: UUID, notAfter: Date?) async throws -> ResetCreditConsumeResult {
        guard expectedAccountFingerprint == account else { throw QuotaServiceError.accountChanged }
        guard notAfter == expiresAt else { throw CheckFailure(message: "自动请求未带到期截止时间") }
        consumeRequests.append(idempotencyKey)
        if consumeFails { throw QuotaServiceError.appServerTimedOut }
        return .reset
    }
}

@main
@MainActor
private struct AppTests {
    static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !condition() { throw CheckFailure(message: message) }
    }

    static func descendants(of view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants(of: $0) }
    }

    static func main() async {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let checks: [(String, () throws -> Void)] = [
            ("详情卡包含自动使用勾选框", checkbox),
            ("详情卡突出余额且低频操作收进菜单", informationHierarchy),
            ("详情卡将数值与标题分列且时区只放提示", compactDetails),
            ("时间条使用中性色以区别额度条", distinctProgressColors),
            ("详情卡包含独立的公共重置公告", publicResetSection),
            ("公告按时区重排且保留刷新禁用状态", publicResetTimeZone),
            ("悬停与展开时保留偏差下划线", underline),
            ("避让麦克风后的额度文字自适应宽度", adaptiveChipTitle),
            ("新详情卡深浅色布局无裁切", popoverLayout),
            ("切换到其他软件仍保留可见窗口的额度", backgroundOverlay),
            ("额度面板不使用全局悬浮层", overlayWindowLevel),
        ]
        var failures = 0
        for (name, body) in checks {
            do {
                try body()
                print("✓ \(name)")
            } catch {
                failures += 1
                print("✗ \(name)：\(error)")
            }
        }
        do {
            try await automaticConsumption()
            print("✓ 自动兑换接入刷新且默认关闭、失败不消费、成功不连兑")
        } catch {
            failures += 1
            print("✗ 自动兑换接入刷新：\(error)")
        }
        do {
            try await PublicResetHTTPTests.run()
            print("✓ 公告 HTTP 隔离凭据、缓存及限流")
        } catch {
            failures += 1
            print("✗ 公告 HTTP：\(error)")
        }
        do {
            try await independentPublicRefresh()
            print("✓ 公告刷新独立于账户且时区变化不触发请求或用券")
        } catch {
            failures += 1
            print("✗ 独立公告刷新：\(error)")
        }
        if failures > 0 { exit(1) }
        print("全部 \(checks.count + 3) 项 AppKit 检查通过")
    }

    static func settle() async throws {
        for _ in 0..<20 { try await Task.sleep(nanoseconds: 10_000_000) }
    }

    static func publicResetSection() throws {
        let controller = QuotaPopoverViewController()
        let labels = descendants(of: controller.view).compactMap { $0 as? NSTextField }
        try expect(labels.contains { $0.stringValue == "Tibo 重置：读取中…" }, "缺少独立公告行")
        try expect(labels.contains { ($0.toolTip ?? "").contains("本机时区") }, "未说明公告使用电脑时区")
        controller.showError(hasCachedStatus: false)
        try expect(labels.contains { $0.stringValue == "Tibo 重置：读取中…" }, "个人额度失败误改公共公告")
    }

    static func informationHierarchy() throws {
        let controller = QuotaPopoverViewController()
        let views = descendants(of: controller.view)
        let labels = views.compactMap { $0 as? NSTextField }
        let buttons = views.compactMap { $0 as? NSButton }
        try expect(labels.contains { $0.stringValue == "剩余" }, "没有独立的余额主标题")
        try expect(labels.contains { $0.stringValue == "时间已过" }, "进度标签含义不明确")
        try expect(views.compactMap { $0 as? NSBox }.filter { $0.boxType == .separator }.count == 3, "没有按内容分成三个区域")
        try expect(!buttons.contains { $0.title == "退出…" }, "退出仍占用常显位置")
        guard let more = buttons.first(where: { $0.title == "更多" }),
              let menu = more.menu, let item = menu.items.first(where: { $0.title == "退出…" }) else {
            throw CheckFailure(message: "更多菜单未保留退出入口")
        }
        var didQuit = false
        controller.onQuit = { didQuit = true }
        menu.performActionForItem(at: menu.index(of: item))
        try expect(didQuit, "退出菜单没有连到原有确认流程")
    }

    static func compactDetails() throws {
        let controller = QuotaPopoverViewController()
        let labels = descendants(of: controller.view).compactMap { $0 as? NSTextField }
        let date = ISO8601DateFormatter().date(from: "2026-09-19T08:11:00Z")!
        controller.update(status: QuotaStatus(remainingPercent: 98, resetsAt: date, windowDurationMins: 10_080,
            planType: "pro", subscriptionActiveUntil: date.addingTimeInterval(9 * 86_400),
            resetCreditsAvailableCount: 3, nearestResetCreditExpiresAt: date,
            fetchedAt: date.addingTimeInterval(-7 * 86_400), warnings: [], accountFingerprint: "demo"),
            timeZone: TimeZone(identifier: "Asia/Shanghai")!)
        controller.updatePublicReset(try PublicResetStatus.parse(PublicResetHTTPTests.fixture), failed: false)
        try expect(labels.contains { $0.stringValue == "98%" }, "余额没有独立展示")
        try expect(labels.contains { $0.stringValue == "7天后重置" }, "重置倒计时没有独立展示")
        try expect(labels.contains { $0.stringValue == "9月19日 16:11" }, "完整重置时间丢失")
        try expect(labels.contains { $0.stringValue == "重置券 3张" }, "重置券数量未放入权益行")
        try expect(!labels.contains { $0.stringValue.contains("Asia/") }, "技术时区名称仍占用界面")
        try expect(labels.contains { ($0.toolTip ?? "").contains("Asia/") }, "收起时区后无法查阅")
    }

    static func distinctProgressColors() throws {
        let controller = QuotaPopoverViewController()
        controller.view.appearance = NSAppearance(named: .aqua)
        let date = Date()
        controller.update(status: QuotaStatus(remainingPercent: 40, resetsAt: date.addingTimeInterval(86_400),
            windowDurationMins: 2880, planType: "pro", subscriptionActiveUntil: nil,
            resetCreditsAvailableCount: 0, nearestResetCreditExpiresAt: nil, fetchedAt: date, warnings: []))
        controller.view.setFrameSize(controller.preferredContentSize)
        controller.view.layoutSubtreeIfNeeded()
        let labels = descendants(of: controller.view).compactMap { $0 as? NSTextField }
        func saturatedPixels(_ title: String) throws -> Int {
            guard let row = labels.first(where: { $0.stringValue == title })?.superview,
                  let bitmap = row.bitmapImageRepForCachingDisplay(in: row.bounds) else {
                throw CheckFailure(message: "无法渲染进度行")
            }
            row.cacheDisplay(in: row.bounds, to: bitmap)
            var count = 0
            for y in 0..<bitmap.pixelsHigh { for x in 0..<bitmap.pixelsWide {
                if let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                   max(c.redComponent, c.greenComponent, c.blueComponent) - min(c.redComponent, c.greenComponent, c.blueComponent) > 0.2 { count += 1 }
            } }
            return count
        }
        try expect(try saturatedPixels("时间已过") < 5, "时间条仍与额度条使用同一强调色")
        try expect(try saturatedPixels("额度已用") > 20, "额度条失去强调色")
        try expect(descendants(of: controller.view).contains {
            $0.accessibilityLabel() == "时间已过" && $0.accessibilityRole() == .progressIndicator
        }, "时间条失去辅助功能进度语义")
    }

    static func publicResetTimeZone() throws {
        let controller = QuotaPopoverViewController()
        let labels = descendants(of: controller.view).compactMap { $0 as? NSTextField }
        let buttons = descendants(of: controller.view).compactMap { $0 as? NSButton }
        let raw = String(decoding: PublicResetHTTPTests.fixture, as: UTF8.self)
            .replacingOccurrences(of: "\"latest_reset\":null", with: """
            "latest_reset":{"reset_type":"regular","announced_at":"2026-09-12T01:30:00Z","text":"Demo announcement","source":{"type":"x_post","author":"thsottiaux","url":"https://x.com/thsottiaux/status/123"}}
            """)
        let status = try PublicResetStatus.parse(Data(raw.utf8))
        let date = ISO8601DateFormatter().date(from: "2026-09-12T01:30:00Z")!
        let account = QuotaStatus(remainingPercent: 50, resetsAt: date, windowDurationMins: 10_080,
            planType: "pro", subscriptionActiveUntil: date, resetCreditsAvailableCount: 1,
            nearestResetCreditExpiresAt: date, fetchedAt: date.addingTimeInterval(-3600),
            warnings: [], accountFingerprint: "demo-account")
        controller.update(status: account)
        controller.showLoading(previousStatus: account)
        controller.updatePublicReset(status, failed: false, timeZone: TimeZone(identifier: "Asia/Shanghai")!)
        try expect(labels.contains { $0.stringValue == "最近重置公告：9月12日 09:30" }, "上海公告时间错误")
        controller.refreshTimeZone(TimeZone(identifier: "America/Los_Angeles")!)
        try expect(labels.contains { $0.stringValue == "最近重置公告：9月11日 18:30" }, "时区变化未重排公告")
        try expect(labels.contains { ($0.toolTip ?? "").contains("America/Los_Angeles") }, "缺少本机时区说明")
        try expect(buttons.first { $0.title == "刷新" }?.isEnabled == false, "时区变化重新启用了刷新按钮")
        try expect(buttons.first { $0.title.hasPrefix("使用重置券") }?.isEnabled == false, "公告刷新启用了用券按钮")
        try expect(labels.contains { $0.stringValue == "9月11日 18:30" }, "个人额度未随时区变化")
        controller.updatePublicReset(status, failed: true)
        try expect(labels.contains { $0.stringValue.contains("显示上次公告") }, "缓存公告未标注过时")
        try expect(labels.contains { $0.stringValue.contains("最近重置公告：") }, "网络失败丢失上次公告")
        controller.updatePublicReset(nil, failed: true)
        try expect(labels.contains { $0.stringValue == "Tibo 重置：暂不可用" }, "失败误显示暂无预告")
        try expect(labels.contains { ($0.toolTip ?? "").contains(TimeZone.autoupdatingCurrent.identifier) }, "公告不可用时丢失本机时区提示")
    }

    static func independentPublicRefresh() async throws {
        let suite = "CodexQuotaAppTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let account = FakeQuotaService()
        let announcements = FakePublicResetService()
        let controller = QuotaOverlayController(service: account, defaults: defaults,
            startMonitoring: false, publicResetService: announcements)
        account.fetchFails = true
        controller.refresh(forceTokenRefresh: false)
        controller.refreshPublicResets()
        try await settle()
        try expect(announcements.fetchCount == 1 && account.fetchCount == 1, "账户失败阻塞公告")
        announcements.fails = true
        controller.refreshPublicResets()
        try await settle()
        try expect(announcements.fetchCount == 2 && account.fetchCount == 1, "公告请求触发账户刷新")
        NotificationCenter.default.post(name: .NSSystemTimeZoneDidChange, object: nil)
        try await settle()
        try expect(announcements.fetchCount == 2 && account.fetchCount == 1 && account.consumeRequests.isEmpty,
                   "时区变化触发网络请求或用券")
    }

    static func overlayWindowLevel() throws {
        let panel = QuotaOverlayPanel()
        try expect(panel.level == .normal, "额度仍使用 floating 层，会盖在其他软件上方")
        try expect(!panel.hidesOnDeactivate, "失去焦点时由 AppKit 自动隐藏")
        try expect(!panel.canBecomeKey && !panel.canBecomeMain, "额度会抢走目标窗口焦点")
    }

    static func backgroundOverlay() throws {
        let target = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 900, height: 600),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        target.orderBack(nil)
        let oldPanels = Set(NSApp.windows.filter { $0 is QuotaOverlayPanel }.map(\.windowNumber))
        let suite = "CodexQuotaAppTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let controller = QuotaOverlayController(service: FakeQuotaService(), defaults: defaults, startMonitoring: false)
        guard let panel = NSApp.windows.first(where: {
            $0 is QuotaOverlayPanel && !oldPanels.contains($0.windowNumber)
        }) else { throw CheckFailure(message: "未找到新建的额度面板") }
        defer {
            panel.orderOut(nil)
            target.orderOut(nil)
            CodexWindowLocator.testWindow = nil
            CodexSidebarLocator.testPlacement = .hidden
            defaults.removePersistentDomain(forName: suite)
        }
        CodexWindowLocator.testWindow = LocatedCodexWindow(
            application: .current, windowID: target.windowNumber,
            frame: target.frame, accessibilityFrame: target.frame
        )
        CodexSidebarLocator.testPlacement = .visible(
            trailingEdgeX: 450, footerCenterBottomInset: 32, trailingControlMinX: 400
        )
        controller.perform(NSSelectorFromString("placementTimerFired"))
        try expect(panel.isVisible, "目标窗口仍可见，仅因切换应用就隐藏额度")

        let other = NSWindow(
            contentRect: NSRect(x: 650, y: 100, width: 300, height: 400),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        defer { other.orderOut(nil) }
        target.orderFrontRegardless()
        other.orderFrontRegardless()
        controller.perform(NSSelectorFromString("placementTimerFired"))
        let windowOrder = (NSWindow.windowNumbers(options: []) ?? []).map(\.intValue)
        guard let overlayIndex = windowOrder.firstIndex(of: panel.windowNumber),
              let targetIndex = windowOrder.firstIndex(of: target.windowNumber),
              let otherIndex = windowOrder.firstIndex(of: other.windowNumber) else {
            throw CheckFailure(message: "测试窗口未进入窗口顺序列表")
        }
        try expect(otherIndex < overlayIndex && overlayIndex < targetIndex,
                   "额度没有保持在目标窗口上方、其他前台窗口下方")

        let movedFrame = target.frame.offsetBy(dx: 40, dy: 20)
        target.setFrame(movedFrame, display: false)
        CodexWindowLocator.testWindow = LocatedCodexWindow(
            application: .current, windowID: target.windowNumber,
            frame: movedFrame, accessibilityFrame: movedFrame
        )
        CodexSidebarLocator.testPlacement = .visible(
            trailingEdgeX: 490, footerCenterBottomInset: 32, trailingControlMinX: 440
        )
        controller.perform(NSSelectorFromString("placementTimerFired"))
        try expect(panel.isVisible && panel.frame == CodexOverlayGeometry.badgeFrame(
            for: movedFrame, sidebarTrailingX: 490,
            footerCenterBottomInset: 32, trailingControlMinX: 440
        ), "后台时额度没有跟随目标窗口移动")

        for placement: CodexSidebarPlacement in [.hidden, .unavailable] {
            CodexSidebarLocator.testPlacement = placement
            controller.perform(NSSelectorFromString("placementTimerFired"))
            try expect(!panel.isVisible, "设置页、收起侧栏或定位不可用时仍残留额度")
        }
        CodexSidebarLocator.testPlacement = .visible(
            trailingEdgeX: 490, footerCenterBottomInset: 32, trailingControlMinX: 440
        )
        controller.perform(NSSelectorFromString("placementTimerFired"))
        try expect(panel.isVisible, "恢复侧栏后额度未重新显示")
        CodexWindowLocator.testWindow = nil
        controller.perform(NSSelectorFromString("placementTimerFired"))
        try expect(!panel.isVisible, "目标窗口最小化、隐藏或不在当前 Space 时仍残留额度")
    }

    static func automaticConsumption() async throws {
        let suite = "CodexQuotaAppTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = FakeQuotaService()
        var controller = QuotaOverlayController(service: service, defaults: defaults, startMonitoring: false)
        controller.refresh(forceTokenRefresh: false)
        try await settle()
        try expect(service.fetchCount == 1 && service.consumeRequests.isEmpty, "默认未勾选却消费了券")

        AutomaticResetCreditAutomation(defaults: defaults).setEnabled(true, for: service.account)
        controller = QuotaOverlayController(service: service, defaults: defaults, startMonitoring: false)
        controller.refresh(forceTokenRefresh: false)
        try await settle()
        try expect(service.consumeRequests.count == 1, "勾选后刷新没有自动消费临期券")
        controller.refresh(forceTokenRefresh: false)
        try await settle()
        try expect(service.consumeRequests.count == 1, "成功后的刷新导致连兑")

        controller = QuotaOverlayController(service: service, defaults: defaults, startMonitoring: false)
        controller.refresh(forceTokenRefresh: false)
        try await settle()
        try expect(service.consumeRequests.count == 1, "重启后再次消费同一到期券")

        service.account = "demo-account-b"
        controller.refresh(forceTokenRefresh: false)
        try await settle()
        try expect(service.consumeRequests.count == 1, "切换账户后沿用自动消费授权")
        service.account = "demo-account-a"
        service.expiresAt = Date().addingTimeInterval(1_600)
        service.fetchFails = true
        controller.refresh(forceTokenRefresh: false)
        try await settle()
        try expect(service.consumeRequests.count == 1, "刷新失败仍消费旧快照的券")
    }

    static func checkbox() throws {
        let controller = QuotaPopoverViewController()
        let buttons = descendants(of: controller.view).compactMap { $0 as? NSButton }
        guard let checkbox = buttons.first(where: { $0.title == "临期自动使用重置券" }) else {
            throw CheckFailure(message: "未找到勾选框")
        }
        try expect(checkbox.state == .off, "初始勾选框未关闭")
        var changes: [Bool] = []
        controller.onAutomaticResetChanged = { changes.append($0) }
        controller.updateAutomaticReset(enabled: false, available: true)
        checkbox.performClick(nil)
        try expect(changes == [true], "勾选没有传递开启状态")
        checkbox.performClick(nil)
        try expect(changes == [true, false], "取消勾选没有传递关闭状态")
        controller.updateAutomaticReset(enabled: true, available: true)
        try expect(checkbox.state == .on, "未展示保存的勾选状态")
        controller.showLoading(previousStatus: nil)
        try expect(!checkbox.isEnabled, "刷新账户时仍可更改勾选")
        controller.updateAutomaticReset(enabled: true, available: true)
        controller.setConsuming(true)
        try expect(!checkbox.isEnabled, "兑换进行中仍可修改勾选")
        controller.updateAutomaticReset(enabled: false, available: false)
        try expect(checkbox.state == .off && !checkbox.isEnabled, "未知账户仍可启用")
    }

    static func orangePixels(in view: NSView) throws -> Int {
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw CheckFailure(message: "无法渲染组件")
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        var count = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.alphaComponent > 0.05,
                   color.redComponent > color.blueComponent + 0.12,
                   color.greenComponent > color.blueComponent + 0.04 { count += 1 }
            }
        }
        return count
    }

    static func popoverLayout() throws {
        let now = ISO8601DateFormatter().date(from: "2026-09-10T04:00:00Z")!
        let status = QuotaStatus(
            remainingPercent: 40, resetsAt: now.addingTimeInterval(4 * 86_400),
            windowDurationMins: 10_080, planType: "pro", subscriptionActiveUntil: now.addingTimeInterval(18 * 86_400),
            resetCreditsAvailableCount: 1, nearestResetCreditExpiresAt: now.addingTimeInterval(1_700),
            fetchedAt: now, warnings: [], accountFingerprint: "demo-account"
        )
        for (name, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
            let controller = QuotaPopoverViewController()
            controller.view.appearance = NSAppearance(named: appearance)
            controller.update(status: status)
            controller.updatePublicReset(try PublicResetStatus.parse(PublicResetHTTPTests.fixture), failed: false,
                timeZone: TimeZone(identifier: "America/Argentina/Buenos_Aires")!)
            controller.updateAutomaticReset(enabled: true, available: true)
            controller.view.setFrameSize(controller.preferredContentSize)
            controller.view.layoutSubtreeIfNeeded()
            for child in descendants(of: controller.view) where child is NSButton || child is NSTextField {
                let rect = child.convert(child.bounds, to: controller.view)
                try expect(controller.view.bounds.insetBy(dx: -1, dy: -1).contains(rect), "详情卡控件超出边界")
            }
            guard let bitmap = controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds) else {
                throw CheckFailure(message: "详情卡不能渲染")
            }
            controller.view.cacheDisplay(in: controller.view.bounds, to: bitmap)
            let output = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
                .appendingPathComponent("automatic-reset-\(name).png")
            try bitmap.representation(using: .png, properties: [:])?.write(to: output)
        }
    }

    static func adaptiveChipTitle() throws {
        let chip = QuotaChipView(frame: NSRect(x: 0, y: 0, width: 220, height: 28))
        let title = "46% · 9月15日 · 5天"
        chip.update(title: title, tooltip: "完整日期与天数", usageDeviation: nil)
        guard let label = chip.subviews.compactMap({ $0 as? NSTextField }).first else {
            throw CheckFailure(message: "未找到额度文字")
        }
        for (width, expected) in [(108.0, "46%·9/15·5天"), (220.0, title), (44.0, "46%"), (220.0, title)] {
            chip.setFrameSize(NSSize(width: width, height: 28))
            chip.layoutSubtreeIfNeeded()
            try expect(chip.bounds.contains(label.frame), "额度文字超出预留后的面板边界")
            try expect((label.cell?.cellSize.width ?? label.intrinsicContentSize.width) <= label.frame.width,
                       "预留麦克风后额度文字被截断")
            try expect(label.stringValue == expected,
                       "宽度 \(width)，实际 \(chip.bounds.width)，文字 \(label.stringValue)，期望 \(expected)")
            try expect(chip.accessibilityLabel()?.contains("完整日期与天数") == true, "精简文字丢失完整辅助功能说明")
        }
    }

    static func underline() throws {
        let chip = QuotaChipView(frame: NSRect(x: 0, y: 0, width: 210, height: 28))
        chip.appearance = NSAppearance(named: .darkAqua)
        chip.update(title: "28% · 9月7日 · 4天", tooltip: "演示", usageDeviation: QuotaUsageDeviation(signedPercentagePoints: 30))
        try expect(try orangePixels(in: chip) > 50, "默认偏差线未显示")
        chip.setExpanded(true)
        try expect(try orangePixels(in: chip) > 50, "展开详情卡时偏差线消失")
        chip.setExpanded(false)
        guard let event = NSEvent.enterExitEvent(
            with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil
        ) else { throw CheckFailure(message: "无法创建悬停事件") }
        chip.mouseEntered(with: event)
        try expect(try orangePixels(in: chip) > 50, "鼠标悬停时偏差线消失")
        chip.setNeedsAttention(true)
        // Attention background is orange, so clear the deviation instead of pixel-testing it.
        chip.setNeedsAttention(false)
        chip.update(title: "--", tooltip: "缺少数据", usageDeviation: nil)
        try expect(try orangePixels(in: chip) == 0, "数据不可比较时仍显示偏差线")
    }
}
