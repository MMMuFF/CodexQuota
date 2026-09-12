import Foundation

enum PublicResetTests {
    static func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
        if !value() { throw NSError(domain: message, code: 1) }
    }

    static func fixture(scheduled: String = "null", watch: String = "null", latest: String = "null") -> Data {
        Data("""
        {"data":{"latest_reset":\(latest),"scheduled_reset":\(scheduled),"active_watch":\(watch)},
         "meta":{"api_version":"v1","generated_at":"2026-09-12T08:00:00.000Z"}}
        """.utf8)
    }

    static let scheduled = """
    {"id":"123","status":"scheduled","reset_type":"regular","announced_at":"2026-09-12T00:00:00Z",
     "scheduled_for":"2026-09-12T01:30:00.000Z","text":"A reset is scheduled.",
     "source":{"type":"x_post","author":"thsottiaux","url":"https://x.com/thsottiaux/status/123"}}
    """

    static func localTimeZones() throws {
        let status = try PublicResetStatus.parse(fixture(scheduled: scheduled))
        let now = ISO8601DateFormatter().date(from: "2026-09-12T00:00:00Z")!
        let shanghai = status.presentation(now: now, timeZone: TimeZone(identifier: "Asia/Shanghai")!)
        let losAngeles = status.presentation(now: now, timeZone: TimeZone(identifier: "America/Los_Angeles")!)
        try check(shanghai.title == "Tibo 重置：预计 9月12日 09:30", "北京时间转换不正确")
        try check(losAngeles.title == "Tibo 重置：预计 9月11日 18:30", "未按夏令时和当地日期转换")
        let winter = scheduled.replacingOccurrences(of: "2026-09-12", with: "2026-12-12")
        let winterStatus = try PublicResetStatus.parse(fixture(scheduled: winter))
        try check(winterStatus.presentation(now: now, timeZone: TimeZone(identifier: "America/Los_Angeles")!).title
            == "Tibo 重置：预计 12月11日 17:30", "冬令时偏移不正确")
        try check(status.presentation(now: now).title == status.presentation(now: now, timeZone: .autoupdatingCurrent).title,
                  "公告默认时区不是系统时区")
    }

    static func scheduledState() throws {
        let now = ISO8601DateFormatter().date(from: "2026-09-12T08:00:00Z")!
        let status = try PublicResetStatus.parse(fixture(scheduled: scheduled))
        let display = status.presentation(now: now, timeZone: .gmt)
        try check(display.title.contains("待确认") && !display.title.contains("已完成"), "预计时间已过却没有保留待确认状态")
        try check(display.sourceURL?.absoluteString == "https://x.com/thsottiaux/status/123", "预告未保留来源")
        let banked = try PublicResetStatus.parse(fixture(scheduled: scheduled.replacingOccurrences(of: "regular", with: "banked")))
        try check(banked.presentation(now: now).title.hasPrefix("Tibo 发券："), "发券被误标为直接重置额度")
        let undated = scheduled.replacingOccurrences(of: "\"2026-09-12T01:30:00.000Z\"", with: "null")
        let pending = try PublicResetStatus.parse(fixture(scheduled: undated))
        try check(pending.presentation(now: now).title == "Tibo 重置：已预告，时间待定", "将公告时间当作预计时间")
    }

    static func watchAndHistory() throws {
        let latest = """
        {"id":"123","reset_type":"banked","announced_at":"2026-09-12T08:09:17Z","text":"Credit granted.",
        "source":{"type":"x_post","author":"thsottiaux","url":"https://x.com/thsottiaux/status/123"}}
        """
        let watch = """
        {"level":"strong","reset_chance_percent":80,"forecast_window":"within a day",
        "observed_at":"2026-09-12T07:00:00Z","expires_at":"2026-09-12T10:00:00Z","text":"A forecast, not a commitment.",
        "source":{"type":"x_post","author":"thsottiaux","url":"https://x.com/thsottiaux/status/124"}}
        """
        let status = try PublicResetStatus.parse(fixture(watch: watch, latest: latest))
        let now = ISO8601DateFormatter().date(from: "2026-09-12T09:00:00Z")!
        let display = status.presentation(now: now, timeZone: TimeZone(identifier: "Asia/Shanghai")!)
        try check(display.title == "重置预测（非官方）：80%", "预测未标注非官方")
        try check(display.latest == "最近发券公告：9月12日 16:09", "公告未区分券或未按当地时间显示")
        try check(!display.title.contains("18:00"), "误将预测失效时间当作预计重置时间")
        try check(status.presentation(now: now.addingTimeInterval(3601)).title == "Tibo 重置：暂无预告", "过期预测仍在显示")
        let precedence = try PublicResetStatus.parse(fixture(scheduled: scheduled, watch: watch, latest: latest))
        try check(precedence.presentation(now: now).title.contains("待确认"), "AI 预测覆盖了明确预告")
    }

    static func malformedAndLinks() throws {
        let valid = String(decoding: fixture(scheduled: scheduled), as: UTF8.self)
        let invalid = [
            valid.replacingOccurrences(of: "\"api_version\":\"v1\"", with: "\"api_version\":\"v2\""),
            valid.replacingOccurrences(of: "2026-09-12T01:30:00.000Z", with: "tomorrow"),
            valid.replacingOccurrences(of: "\"regular\"", with: "\"unknown\""),
            String(decoding: fixture(), as: UTF8.self).replacingOccurrences(of: "\"latest_reset\":null,", with: "")
        ]
        for raw in invalid {
            var rejected = false
            do { _ = try PublicResetStatus.parse(Data(raw.utf8)) } catch { rejected = true }
            try check(rejected, "损坏的公共状态被当作暂无预告")
        }
        for url in ["javascript:alert(1)", "https://evil.example/reset", "https://x.com/thsottiaux/status/123?redirect=bad"] {
            let unsafe = scheduled.replacingOccurrences(of: "https://x.com/thsottiaux/status/123", with: url)
            let status = try PublicResetStatus.parse(fixture(scheduled: unsafe))
            try check(status.presentation().sourceURL == nil, "允许打开不可信来源链接")
        }
        let otherAuthor = scheduled.replacingOccurrences(of: "thsottiaux", with: "someone_else")
        let unattributed = try PublicResetStatus.parse(fixture(scheduled: otherAuthor))
        try check(!unattributed.presentation().title.hasPrefix("Tibo"), "将其他来源冒充为 Tibo")
        let latest = """
        {"reset_type":"regular","announced_at":"2026-09-11T08:00:00Z","text":"Old announcement",
        "source":{"type":"x_post","author":"thsottiaux","url":"https://x.com/thsottiaux/status/122"}}
        """
        let unsafeCurrent = scheduled.replacingOccurrences(of: "https://x.com/thsottiaux/status/123", with: "https://evil.example/reset")
        let mixed = try PublicResetStatus.parse(fixture(scheduled: unsafeCurrent, latest: latest))
        try check(mixed.presentation().sourceURL == nil, "预告来源无效却打开了旧公告")
    }

    static func confidenceSemantics() throws {
        let now = ISO8601DateFormatter().date(from: "2026-09-12T00:30:00Z")!
        let watch = """
        {"level":"strong","reset_chance_percent":80,"forecast_window":"soon",
        "observed_at":"2026-09-12T00:00:00Z","expires_at":"2026-09-12T10:00:00Z","text":"Possible reset",
        "source":{"type":"x_post","author":"thsottiaux","url":"https://x.com/thsottiaux/status/124"}}
        """
        func present(_ raw: String) throws -> PublicResetPresentation {
            try PublicResetStatus.parse(fixture(watch: raw)).presentation(now: now)
        }
        let strong = try present(watch)
        try check(strong.detail.contains("信号较强") && strong.detail.contains("非执行保证"), "预测缺少信号强度与风险提示")
        try check(strong.detail.contains("未提供历史命中率"), "预测概率被当作已验证准确率")
        let elevated = try present(watch.replacingOccurrences(of: "strong", with: "elevated"))
        try check(elevated.detail.contains("信号增强"), "增强信号误当强信号")
        let unknown = try present(watch.replacingOccurrences(of: "strong", with: "future_level"))
        try check(unknown.detail.contains("强度未知") && !unknown.detail.contains("信号较强"), "未知级别误报强信号")
        let noChance = try present(watch.replacingOccurrences(of: "\"reset_chance_percent\":80", with: "\"reset_chance_percent\":null"))
        try check(noChance.title.contains("概率未提供") && !noChance.title.contains("%"), "缺少概率时伪造百分比")
        let announced = try PublicResetStatus.parse(fixture(scheduled: scheduled, watch: watch)).presentation(now: now)
        try check(announced.detail.contains("已预告 · 待执行") && !announced.title.contains("80%"), "预告误用预测概率或未区分执行状态")
        let late = try PublicResetStatus.parse(fixture(scheduled: scheduled)).presentation(now: now.addingTimeInterval(7200))
        try check(late.detail.contains("预告时间已过 · 待确认"), "到点自动当作完成")
        let history = scheduled.replacingOccurrences(of: "\"status\":\"scheduled\",", with: "")
        let past = try PublicResetStatus.parse(fixture(latest: history)).presentation(now: now)
        try check(past.detail.contains("已发布公告 · 非个人到账确认"), "历史公告未区别个人到账")
        let observed = history.replacingOccurrences(of: "\"type\":\"x_post\"", with: "\"type\":\"observed\"")
        let observation = try PublicResetStatus.parse(fixture(latest: observed)).presentation(now: now)
        try check(observation.detail.contains("第三方观测 · 非官方确认"), "观测被当作官方公告")
    }

    static func accountTimeZoneDefaults() throws {
        let date = ISO8601DateFormatter().date(from: "2026-09-12T01:30:00Z")!
        let status = QuotaStatus(remainingPercent: 50, resetsAt: date, windowDurationMins: 10_080,
            planType: "pro", subscriptionActiveUntil: date, resetCreditsAvailableCount: 1,
            nearestResetCreditExpiresAt: date, fetchedAt: date.addingTimeInterval(-3600), warnings: [])
        try check(QuotaDisplayFormatter.hoverTitle(for: status)
            == QuotaDisplayFormatter.hoverTitle(for: status, timeZone: .autoupdatingCurrent), "个人额度默认仍写死北京时间")
        try check(QuotaDisplayFormatter.tooltip(for: status)
            == QuotaDisplayFormatter.tooltip(for: status, timeZone: .autoupdatingCurrent), "会员或重置券默认仍写死北京时间")
    }
}
