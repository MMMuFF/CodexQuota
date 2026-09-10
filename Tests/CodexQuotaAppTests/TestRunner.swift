import AppKit
import CodexQuotaCore

private struct CheckFailure: Error { let message: String }

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
            ("悬停与展开时保留偏差下划线", underline),
            ("新详情卡深浅色布局无裁切", popoverLayout),
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
        if failures > 0 { exit(1) }
        print("全部 \(checks.count + 1) 项 AppKit 检查通过")
    }

    static func settle() async throws {
        for _ in 0..<20 { try await Task.sleep(nanoseconds: 10_000_000) }
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
