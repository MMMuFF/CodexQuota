import Darwin
import Foundation

private struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

private enum LaunchAtLoginFixtureError: Error {
    case registrationFailed
}

private final class FakeLaunchAtLoginService: LaunchAtLoginService {
    var status: LaunchAtLoginStatus
    var shouldFail = false
    private(set) var registrationCount = 0

    init(status: LaunchAtLoginStatus) {
        self.status = status
    }

    func register() throws {
        registrationCount += 1
        if shouldFail {
            throw LaunchAtLoginFixtureError.registrationFailed
        }
        status = .enabled
    }
}

@main
private struct CodexQuotaCoreTestRunner {
    private typealias Check = (name: String, body: () throws -> Void)

    static func main() {
        let checks: [Check] = [
            ("真实 7 天结构得到 39% 剩余", liveRateLimitShape),
            ("多窗口选择最长周期", longestWindowWins),
            ("JWT 订阅字段本机解码", jwtSubscriptionClaim),
            ("重置券选择最早可用到期项", nearestResetCreditExpiration),
            ("app-server 券明细兼容", appServerResetCreditDetails),
            ("消费结果纯解析", consumeOutcomes),
            ("消费请求只含幂等 ID", consumeRequestShape),
            ("重置券请求按账户与时间隔离", resetCreditAccountScope),
            ("重置券接口拒绝重定向", resetCreditRedirectPolicy),
            ("Codex 路径不信任任意 PATH", codexExecutableCandidates),
            ("北京时间中文短文案", chineseDateFormatting),
            ("重置券未知状态不误报为空", resetCreditPresentationStates),
            ("选择最前方 Codex 主窗口", overlayWindowSelection),
            ("窗口坐标转换为 AppKit 坐标", overlayCoordinateConversion),
            ("额度组件落在昵称右侧", overlayBadgePlacement),
            ("额度组件跟随账户底栏中心线", overlayBadgeFollowsFooterCenter),
            ("侧边栏变化时额度文字保持居中", overlayBadgeFollowsSidebar),
            ("侧边栏隐藏几何判定", overlaySidebarVisibility),
            ("仅任务页账户底栏显示组件", overlayTaskSidebarFooter),
            ("临时对话框不误判为设置页", overlayTransientDialogRecognition),
            ("侧边栏拖动瞬态保持显示", overlaySidebarResizeContinuity),
            ("登录启动注册策略幂等", launchAtLoginCoordination),
            ("短 JSON 行无需等待管道关闭", shortJSONLineDelivery),
        ]

        var failures = 0
        for check in checks {
            do {
                try check.body()
                print("✓ \(check.name)")
            } catch {
                failures += 1
                print("✗ \(check.name)：\(error)")
            }
        }

        if failures > 0 {
            print("\n\(failures) 项检查失败")
            exit(1)
        }
        print("\n全部 \(checks.count) 项检查通过")
    }

    private static func liveRateLimitShape() throws {
        let fixture = """
        {
          "rateLimits": {
            "limitId": "codex",
            "planType": "pro",
            "primary": {
              "usedPercent": 61,
              "windowDurationMins": 10080,
              "resetsAt": 1784908800
            },
            "secondary": null
          },
          "rateLimitsByLimitId": {
            "codex": {
              "limitId": "codex",
              "planType": "pro",
              "primary": {
                "usedPercent": 61,
                "windowDurationMins": 10080,
                "resetsAt": 1784908800
              }
            }
          },
          "rateLimitResetCredits": {
            "availableCount": 7,
            "credits": null
          }
        }
        """
        let data = try require(fixture.data(using: .utf8), "fixture 编码失败")
        let rateLimits = try JSONSerialization.jsonObject(with: data)
        let parsed = try RateLimitParser.parse(
            accountResult: ["account": ["type": "chatgpt", "planType": "pro"]],
            rateLimitResult: rateLimits
        )

        try expect(parsed.remainingPercent == 39, "剩余比例应为 39%")
        try expect(parsed.windowDurationMins == 10_080, "周期应为 7 天")
        try expect(parsed.planType == "pro", "计划应为 Pro")
        try expect(parsed.resetCreditsAvailableCount == 7, "可用券数量错误")
        try expect(!parsed.hasResetCreditDetails, "null 明细不应标记为完整")
    }

    private static func longestWindowWins() throws {
        let result: JSONDictionary = [
            "rateLimits": [
                "primary": [
                    "usedPercent": 10,
                    "windowDurationMins": 300,
                    "resetsAt": 1_784_820_000
                ],
                "secondary": [
                    "usedPercent": 61,
                    "windowDurationMins": 10_080,
                    "resetsAt": 1_784_908_800
                ]
            ]
        ]
        let parsed = try RateLimitParser.parse(accountResult: nil, rateLimitResult: result)

        try expect(parsed.remainingPercent == 39, "未选择长周期比例")
        try expect(parsed.windowDurationMins == 10_080, "未选择 7 天窗口")
        try expect(
            parsed.resetsAt == Date(timeIntervalSince1970: 1_784_908_800),
            "刷新时间错误"
        )
    }

    private static func jwtSubscriptionClaim() throws {
        let payload: JSONDictionary = [
            "https://api.openai.com/auth": [
                "chatgpt_plan_type": "pro",
                "chatgpt_account_id": "account-for-fixture-only",
                "chatgpt_subscription_active_until": "2026-07-30T16:00:00Z"
            ]
        ]
        let payloadData = try JSONSerialization.data(withJSONObject: payload)
        let token = "e30.\(base64URL(payloadData)).fixture-signature"
        let authData = try JSONSerialization.data(withJSONObject: [
            "tokens": [
                "id_token": token,
                "account_id": "fixture-account"
            ]
        ])
        let auth = try require(AuthFileParser.parse(authData), "JWT 解析失败")

        try expect(
            auth.subscriptionActiveUntil
                == ISO8601DateFormatter().date(from: "2026-07-30T16:00:00Z"),
            "订阅结束时间错误"
        )
        try expect(auth.planType == "pro", "JWT 计划错误")
    }

    private static func nearestResetCreditExpiration() throws {
        let fixture = """
        {
          "data": {
            "available_count": 2,
            "credits": [
              {"status": "redeemed", "expires_at": "2026-07-20T00:00:00Z"},
              {"status": "available", "expires_at": "2026-07-26T00:30:00Z"},
              {"status": "available", "expires_at": "2026-07-25T00:30:00Z"}
            ]
          }
        }
        """
        let data = try require(fixture.data(using: .utf8), "fixture 编码失败")
        let summary = try ResetCreditParser.parseHTTPResponse(data)

        try expect(summary.availableCount == 2, "券数量错误")
        try expect(
            summary.nearestExpiresAt
                == ISO8601DateFormatter().date(from: "2026-07-25T00:30:00Z"),
            "未选择最早可用券"
        )
    }

    private static func appServerResetCreditDetails() throws {
        let summary = ResetCreditParser.parseAppServerSummary([
            "availableCount": 2,
            "credits": [
                ["status": "available", "expiresAt": 1_784_948_400],
                ["status": "available", "expiresAt": 1_784_862_000],
                ["status": "redeemed", "expiresAt": 1_700_000_000]
            ]
        ])

        try expect(summary.hasDetails, "应识别 app-server 明细")
        try expect(summary.availableCount == 2, "app-server 券数量错误")
        try expect(
            summary.nearestExpiresAt == Date(timeIntervalSince1970: 1_784_862_000),
            "app-server 最近到期时间错误"
        )

        let emptySummary = ResetCreditParser.parseAppServerSummary([
            "availableCount": 0,
            "credits": []
        ])
        try expect(emptySummary.hasDetails, "空券数组应代表详情已成功读取")
        try expect(emptySummary.availableCount == 0, "空券数组数量错误")
    }

    private static func consumeOutcomes() throws {
        try expect(
            ResetCreditConsumeParser.parse(["outcome": "reset"]) == .reset,
            "reset 解析失败"
        )
        try expect(
            ResetCreditConsumeParser.parse(["outcome": "alreadyRedeemed"])
                == .alreadyRedeemed,
            "alreadyRedeemed 解析失败"
        )
        try expect(
            ResetCreditConsumeParser.parse(["outcome": "nothingToReset"])
                == .nothingToReset,
            "nothingToReset 解析失败"
        )
        try expect(
            ResetCreditConsumeParser.parse(["outcome": "noCredit"]) == .noCredit,
            "noCredit 解析失败"
        )
        try expect(ResetCreditConsumeResult.reset.succeeded, "reset 应视为成功")
        try expect(
            ResetCreditConsumeResult.alreadyRedeemed.succeeded,
            "alreadyRedeemed 应视为成功"
        )
        try expect(!ResetCreditConsumeResult.noCredit.succeeded, "noCredit 不应视为成功")
    }

    private static func consumeRequestShape() throws {
        let forcedAccountRequest = try require(
            AppServerRequestFactory.fetchRequests(forceTokenRefresh: true)
                .first(where: { ($0["id"] as? Int) == 1 }),
            "缺少强制账户读取请求"
        )
        let forcedAccountParams = try require(
            forcedAccountRequest["params"] as? JSONDictionary,
            "强制账户读取缺少 params"
        )
        try expect(
            forcedAccountParams["refreshToken"] as? Bool == true,
            "换号后的账户读取未强制刷新"
        )

        let regularAccountRequest = try require(
            AppServerRequestFactory.fetchRequests(forceTokenRefresh: false)
                .first(where: { ($0["id"] as? Int) == 1 }),
            "缺少普通账户读取请求"
        )
        let regularAccountParams = try require(
            regularAccountRequest["params"] as? JSONDictionary,
            "普通账户读取缺少 params"
        )
        try expect(
            regularAccountParams["refreshToken"] as? Bool == false,
            "定时账户读取不应强制刷新"
        )

        let key = try require(
            UUID(uuidString: "00000000-0000-4000-8000-000000000123"),
            "UUID fixture 无效"
        )
        let request = try require(
            AppServerRequestFactory.consumeRequests(idempotencyKey: key).last,
            "缺少消费请求"
        )
        let params = try require(request["params"] as? JSONDictionary, "缺少 params")

        try expect(
            request["method"] as? String == "account/rateLimitResetCredit/consume",
            "消费方法错误"
        )
        try expect(params["idempotencyKey"] as? String == key.uuidString, "幂等 ID 错误")
        try expect(params.count == 1, "消费请求包含多余字段")
    }

    private static func resetCreditAccountScope() throws {
        let accountA = try require(
            AccountIdentityParser.fingerprint(
                authAccountID: "account-a"
            ),
            "账户 A 指纹缺失"
        )
        let accountANormalized = try require(
            AccountIdentityParser.fingerprint(
                authAccountID: "  account-a  "
            ),
            "规范化账户 A 指纹缺失"
        )
        let accountB = try require(
            AccountIdentityParser.fingerprint(
                authAccountID: "account-b"
            ),
            "账户 B 指纹缺失"
        )
        try expect(accountA == accountANormalized, "账户 ID 空白规范化失败")
        try expect(accountA != accountB, "不同账户得到相同指纹")
        try expect(
            AccountIdentityParser.fingerprint(authAccountID: nil) == nil,
            "缺少稳定账户 ID 时仍生成了指纹"
        )
        try expect(
            AccountIdentityParser.fingerprint(authAccountID: "  ") == nil,
            "空账户 ID 时仍生成了指纹"
        )

        try ResetCreditAccountGuard.validate(
            expectedFingerprint: accountA,
            currentFingerprint: accountA
        )
        do {
            try ResetCreditAccountGuard.validate(
                expectedFingerprint: accountA,
                currentFingerprint: accountB
            )
            throw CheckFailure(description: "账户切换后仍允许消费")
        } catch let error as QuotaServiceError {
            try expect(error == .accountChanged, "账户切换错误类型不正确")
        }

        let createdAt = Date(timeIntervalSince1970: 1_000)
        let request = PendingResetCreditRequest(
            accountFingerprint: accountA,
            idempotencyKey: UUID(),
            createdAt: createdAt
        )
        try expect(
            request.isReusable(
                for: accountA,
                now: createdAt.addingTimeInterval(60)
            ),
            "同账户短期重试未复用幂等请求"
        )
        try expect(
            !request.isReusable(
                for: accountB,
                now: createdAt.addingTimeInterval(60)
            ),
            "幂等请求跨账户复用"
        )
        try expect(
            !request.isReusable(
                for: accountA,
                now: createdAt.addingTimeInterval(
                    PendingResetCreditRequest.defaultMaximumAge + 1
                )
            ),
            "过期幂等请求仍被复用"
        )
    }

    private static func resetCreditRedirectPolicy() throws {
        let request = URLRequest(
            url: try require(
                URL(string: "https://example.com/redirected"),
                "重定向 URL 无效"
            )
        )
        try expect(
            ResetCreditRedirectPolicy.redirectedRequest(request) == nil,
            "携带凭据的请求仍允许重定向"
        )
    }

    private static func codexExecutableCandidates() throws {
        let candidates = CodexExecutableLocator.candidatePaths(
            environment: [
                "CODEX_QUOTA_CODEX_PATH": "/private/tmp/trusted-codex",
                "PATH": "/private/tmp/untrusted-bin:/usr/bin",
            ]
        )
        try expect(
            candidates == [
                "/private/tmp/trusted-codex",
                "/Applications/ChatGPT.app/Contents/Resources/codex",
            ],
            "候选路径意外包含 PATH 中的可执行文件"
        )
    }

    private static func chineseDateFormatting() throws {
        let resetsAt = try require(
            ISO8601DateFormatter().date(from: "2026-07-25T05:19:00Z"),
            "刷新日期无效"
        )
        let subscriptionUntil = try require(
            ISO8601DateFormatter().date(from: "2026-07-30T16:00:00Z"),
            "订阅日期无效"
        )
        let creditExpiresAt = try require(
            ISO8601DateFormatter().date(from: "2026-07-25T00:30:00Z"),
            "券日期无效"
        )
        let fetchedAt = try require(
            ISO8601DateFormatter().date(from: "2026-07-21T09:00:00Z"),
            "更新时间无效"
        )
        let shanghai = try require(TimeZone(identifier: "Asia/Shanghai"), "缺少上海时区")
        let status = QuotaStatus(
            remainingPercent: 39,
            resetsAt: resetsAt,
            windowDurationMins: 10_080,
            planType: "pro",
            subscriptionActiveUntil: subscriptionUntil,
            resetCreditsAvailableCount: 7,
            nearestResetCreditExpiresAt: creditExpiresAt,
            fetchedAt: fetchedAt,
            warnings: []
        )

        try expect(
            QuotaDisplayFormatter.mainTitle(for: status, timeZone: shanghai)
                == "39% · 7月25日 · 4天",
            "主文案错误"
        )
        try expect(
            QuotaDisplayFormatter.hoverTitle(for: status, timeZone: shanghai)
                == "39% · 7月25日 13:19 · 4天",
            "悬浮标题错误"
        )
        try expect(
            QuotaDisplayFormatter.tooltip(for: status, timeZone: shanghai)
                == "39% · 7月25日 13:19 · 4天\nPro 到期：7月31日 · 10天\n最早到期券：7月25日 08:30 · 4天",
            "悬停文案错误"
        )

        let noCreditStatus = QuotaStatus(
            remainingPercent: status.remainingPercent,
            resetsAt: status.resetsAt,
            windowDurationMins: status.windowDurationMins,
            planType: status.planType,
            subscriptionActiveUntil: status.subscriptionActiveUntil,
            resetCreditsAvailableCount: 0,
            nearestResetCreditExpiresAt: nil,
            fetchedAt: status.fetchedAt,
            warnings: []
        )
        try expect(
            QuotaDisplayFormatter.tooltip(for: noCreditStatus, timeZone: shanghai)
                == "39% · 7月25日 13:19 · 4天\nPro 到期：7月31日 · 10天\n重置券：暂无",
            "无重置券文案错误"
        )

        let plusStatus = QuotaStatus(
            remainingPercent: status.remainingPercent,
            resetsAt: status.resetsAt,
            windowDurationMins: status.windowDurationMins,
            planType: "plus",
            subscriptionActiveUntil: status.subscriptionActiveUntil,
            resetCreditsAvailableCount: status.resetCreditsAvailableCount,
            nearestResetCreditExpiresAt: status.nearestResetCreditExpiresAt,
            fetchedAt: status.fetchedAt,
            warnings: []
        )
        try expect(
            QuotaDisplayFormatter.subscriptionExpirationText(
                for: plusStatus,
                timeZone: shanghai
            ) == "Plus 到期：7月31日 · 10天",
            "Plus 到期文案错误"
        )

        let proLiteStatus = QuotaStatus(
            remainingPercent: status.remainingPercent,
            resetsAt: status.resetsAt,
            windowDurationMins: status.windowDurationMins,
            planType: "prolite",
            subscriptionActiveUntil: status.subscriptionActiveUntil,
            resetCreditsAvailableCount: status.resetCreditsAvailableCount,
            nearestResetCreditExpiresAt: status.nearestResetCreditExpiresAt,
            fetchedAt: status.fetchedAt,
            warnings: []
        )
        try expect(
            QuotaDisplayFormatter.subscriptionExpirationText(
                for: proLiteStatus,
                timeZone: shanghai
            ) == "Pro Lite 到期：7月31日 · 10天",
            "Pro Lite 到期文案错误"
        )

        let nextDay = try require(
            ISO8601DateFormatter().date(from: "2026-07-21T16:01:00Z"),
            "次日日期无效"
        )
        try expect(
            QuotaDisplayFormatter.remainingCalendarDays(
                until: nextDay,
                from: fetchedAt,
                timeZone: shanghai
            ) == 1,
            "自然日期跨日应显示 1 天"
        )
    }

    private static func overlayWindowSelection() throws {
        let snapshots = [
            CodexWindowSnapshot(
                windowID: 5,
                frame: CGRect(x: 250, y: 180, width: 900, height: 650),
                layer: 0,
                isOnScreen: true,
                alpha: 1,
                order: 0
            ),
            CodexWindowSnapshot(
                windowID: 1,
                frame: CGRect(x: 0, y: 0, width: 1_700, height: 1_000),
                layer: 0,
                isOnScreen: false,
                alpha: 1,
                order: 0
            ),
            CodexWindowSnapshot(
                windowID: 2,
                frame: CGRect(x: 0, y: 0, width: 1_700, height: 33),
                layer: 0,
                isOnScreen: true,
                alpha: 1,
                order: 1
            ),
            CodexWindowSnapshot(
                windowID: 3,
                frame: CGRect(x: 80, y: 50, width: 1_200, height: 800),
                layer: 0,
                isOnScreen: true,
                alpha: 1,
                order: 3
            ),
            CodexWindowSnapshot(
                windowID: 4,
                frame: CGRect(x: 58, y: 33, width: 1_670, height: 1_084),
                layer: 0,
                isOnScreen: true,
                alpha: 1,
                order: 2
            ),
        ]

        try expect(
            CodexOverlayGeometry.mainWindow(in: snapshots)?.windowID == 4,
            "未排除较小弹窗并选择有效主窗口"
        )
    }

    private static func resetCreditPresentationStates() throws {
        let unknown = QuotaDisplayFormatter.resetCreditActionState(availableCount: nil)
        try expect(unknown.title == "重置券暂不可用", "未知状态按钮文案错误")
        try expect(!unknown.isEnabled, "未知状态不应允许使用重置券")

        let empty = QuotaDisplayFormatter.resetCreditActionState(availableCount: 0)
        try expect(empty.title == "暂无重置券", "零张状态按钮文案错误")
        try expect(!empty.isEnabled, "零张状态不应允许使用重置券")

        let available = QuotaDisplayFormatter.resetCreditActionState(availableCount: 6)
        try expect(available.title == "使用重置券（6）", "可用状态按钮文案错误")
        try expect(available.isEnabled, "可用状态应允许使用重置券")

        let unknownStatus = QuotaStatus(
            remainingPercent: 93,
            resetsAt: nil,
            windowDurationMins: 10_080,
            planType: "pro",
            subscriptionActiveUntil: nil,
            resetCreditsAvailableCount: nil,
            nearestResetCreditExpiresAt: nil,
            fetchedAt: Date(timeIntervalSince1970: 0),
            warnings: ["重置券详情暂不可用"]
        )
        try expect(
            QuotaDisplayFormatter.resetCreditDetailText(for: unknownStatus)
                == "重置券：暂不可用",
            "未知状态详情文案错误"
        )
        try expect(
            QuotaDisplayFormatter.freshnessText(for: unknownStatus)
                == "重置券详情暂不可用，主额度已更新",
            "未知状态提示文案错误"
        )
    }

    private static func overlayCoordinateConversion() throws {
        let frame = CodexOverlayGeometry.appKitWindowFrame(
            fromCoreGraphics: CGRect(x: 58, y: 33, width: 1_670, height: 1_084),
            primaryScreenMaxY: 1_117
        )

        try expect(
            frame == CGRect(x: 58, y: 0, width: 1_670, height: 1_084),
            "CoreGraphics 与 AppKit 的纵坐标转换错误"
        )
    }

    private static func overlayBadgePlacement() throws {
        let frame = CodexOverlayGeometry.badgeFrame(
            for: CGRect(x: 58, y: 0, width: 1_670, height: 1_084)
        )

        try expect(
            frame == CGRect(x: 176, y: 19, width: 154, height: 28),
            "组件未落在截图标注的昵称右侧位置"
        )
    }

    private static func overlayBadgeFollowsFooterCenter() throws {
        let sidebar = CGRect(x: 258, y: 209, width: 275, height: 970)
        let footerMetrics = try require(
            CodexOverlayGeometry.taskSidebarFooterMetrics(
                sidebarFrame: sidebar,
                accountControlFrame: CGRect(x: 266, y: 1_142, width: 219, height: 29),
                trailingButtonFrame: CGRect(x: 493, y: 1_140, width: 32, height: 32)
            ),
            "未取得当前紧凑账户底栏中心"
        )
        try expect(
            abs(footerMetrics.centerBottomInset - 22.75) < 0.001,
            "账户底栏中心距底部计算错误"
        )
        try expect(
            footerMetrics.trailingControlMinX == 493,
            "未取得右侧问号的真实左边界"
        )

        let window = CGRect(x: 258, y: 333, width: 1_679, height: 970)
        let frame = CodexOverlayGeometry.badgeFrame(
            for: window,
            sidebarTrailingX: sidebar.maxX,
            footerCenterBottomInset: footerMetrics.centerBottomInset,
            trailingControlMinX: footerMetrics.trailingControlMinX
        )
        try expect(
            abs(frame.midY - (window.minY + footerMetrics.centerBottomInset)) < 0.001,
            "额度组件没有与昵称和问号保持同一中心线"
        )
        try expect(
            abs(frame.minY - 341.75) < 0.001,
            "额度组件仍在使用固定的底部偏移"
        )
        try expect(
            abs(frame.maxX - 489) < 0.001,
            "额度组件没有给右侧问号留出空间"
        )
        try expect(
            CGRect(x: 493, y: 1_140, width: 32, height: 32).minX - frame.maxX >= 4,
            "额度组件与右侧问号发生重叠"
        )
    }

    private static func overlayBadgeFollowsSidebar() throws {
        let windowFrame = CGRect(x: 58, y: 0, width: 1_670, height: 1_084)
        let current = CodexOverlayGeometry.badgeFrame(
            for: windowFrame,
            sidebarTrailingX: 394
        )
        let widened = CodexOverlayGeometry.badgeFrame(
            for: windowFrame,
            sidebarTrailingX: 474
        )

        try expect(
            current == CGRect(x: 176, y: 19, width: 154, height: 28),
            "当前侧边栏宽度下的位置发生偏移"
        )
        try expect(widened.origin.x == current.origin.x, "动态面板左边界不稳定")
        try expect(widened.width == current.width + 80, "动态面板没有跟随侧边栏变宽")
        try expect(widened.midX == current.midX + 40, "额度文字没有保持在可用区域中央")
    }

    private static func overlaySidebarVisibility() throws {
        let windowFrame = CGRect(x: 58, y: 33, width: 1_670, height: 1_084)
        try expect(
            CodexOverlayGeometry.isSidebarVisible(
                sidebarFrame: CGRect(x: 58, y: 33, width: 336, height: 1_084),
                within: windowFrame
            ),
            "展开的侧边栏被误判为隐藏"
        )
        try expect(
            !CodexOverlayGeometry.isSidebarVisible(
                sidebarFrame: CGRect(x: 58, y: 33, width: 0, height: 1_084),
                within: windowFrame
            ),
            "零宽侧边栏仍被判定为可见"
        )
        try expect(
            !CodexOverlayGeometry.isSidebarVisible(
                sidebarFrame: nil,
                within: windowFrame
            ),
            "缺失侧边栏仍被判定为可见"
        )
        try expect(
            CodexOverlayGeometry.isMainContentFullWidth(
                mainContentFrame: windowFrame,
                within: windowFrame
            ),
            "铺满窗口的主内容未被识别"
        )
        try expect(
            !CodexOverlayGeometry.isMainContentFullWidth(
                mainContentFrame: CGRect(x: 394, y: 33, width: 1_334, height: 1_084),
                within: windowFrame
            ),
            "展开侧边栏时的主内容被误判为全宽"
        )
    }

    private static func overlayTaskSidebarFooter() throws {
        let sidebar = CGRect(x: 58, y: 33, width: 336, height: 1_084)
        try expect(
            CodexOverlayGeometry.isTaskSidebarFooter(
                sidebarFrame: sidebar,
                accountControlFrame: CGRect(x: 69, y: 1_065, width: 275, height: 41),
                trailingButtonFrame: CGRect(x: 355, y: 1_071, width: 28, height: 28)
            ),
            "正常任务页账户底栏未被识别"
        )
        try expect(
            CodexOverlayGeometry.isTaskSidebarFooter(
                sidebarFrame: CGRect(x: 63, y: 33, width: 336, height: 1_084),
                accountControlFrame: CGRect(x: 74, y: 1_065, width: 258, height: 41),
                trailingButtonFrame: CGRect(x: 343, y: 1_062, width: 45, height: 46)
            ),
            "新版双下拉任务页账户底栏未被识别"
        )
        try expect(
            CodexOverlayGeometry.isTaskSidebarFooter(
                sidebarFrame: CGRect(x: 87, y: 30, width: 384, height: 1_590),
                accountControlFrame: CGRect(x: 100, y: 1_560, width: 295, height: 47),
                trailingButtonFrame: CGRect(x: 407, y: 1_558, width: 52, height: 51)
            ),
            "当前 Codex 大尺寸账户底栏未被识别"
        )
        try expect(
            CodexOverlayGeometry.isTaskSidebarFooter(
                sidebarFrame: CGRect(x: 258, y: 209, width: 275, height: 1_249),
                accountControlFrame: CGRect(x: 266, y: 1_421, width: 219, height: 29),
                trailingButtonFrame: CGRect(x: 493, y: 1_419, width: 32, height: 32)
            ),
            "紧凑任务页账户底栏未被识别"
        )
        try expect(
            !CodexOverlayGeometry.isTaskSidebarFooter(
                sidebarFrame: sidebar,
                accountControlFrame: CGRect(x: 69, y: 1_065, width: 258, height: 41),
                trailingButtonFrame: CGRect(x: 346, y: 1_082, width: 35, height: 34)
            ),
            "设置页底部控件被误判为账户底栏"
        )
        try expect(
            !CodexOverlayGeometry.isTaskSidebarFooter(
                sidebarFrame: sidebar,
                accountControlFrame: nil,
                trailingButtonFrame: nil
            ),
            "缺失账户底栏时仍显示组件"
        )

        let widenedSidebar = CGRect(x: 58, y: 33, width: 440, height: 1_084)
        try expect(
            CodexOverlayGeometry.isTaskSidebarFooter(
                sidebarFrame: widenedSidebar,
                accountControlFrame: CGRect(x: 69, y: 1_065, width: 379, height: 41),
                trailingButtonFrame: CGRect(x: 459, y: 1_071, width: 28, height: 28)
            ),
            "侧边栏变宽后账户底栏识别失败"
        )
    }

    private static func overlayTransientDialogRecognition() throws {
        try expect(
            CodexOverlayGeometry.isTransientAccessibilityOverlay(
                role: "AXGroup",
                subrole: "AXApplicationDialog"
            ),
            "应用对话框未被识别为临时遮罩"
        )
        try expect(
            CodexOverlayGeometry.isTransientAccessibilityOverlay(
                role: "AXSheet",
                subrole: nil
            ),
            "Sheet 未被识别为临时遮罩"
        )
        try expect(
            !CodexOverlayGeometry.isTransientAccessibilityOverlay(
                role: "AXGroup",
                subrole: "AXLandmarkComplementary"
            ),
            "普通侧边栏被误判为临时遮罩"
        )
    }

    private static func overlaySidebarResizeContinuity() throws {
        var continuity = CodexTaskSidebarContinuity()
        try expect(
            continuity.decision(
                for: .temporarilyUnavailable(trailingEdgeX: nil),
                timestamp: 0
            ) == .hidden,
            "尚未确认任务页时不应凭移动宽限显示"
        )
        try expect(
            continuity.decision(
                for: .task(trailingEdgeX: 394),
                timestamp: 2
            ) == .visible(trailingEdgeX: 394),
            "任务页确认后未显示"
        )
        try expect(
            continuity.decision(
                for: .temporarilyUnavailable(trailingEdgeX: 430),
                timestamp: 2.1
            ) == .visible(trailingEdgeX: 430),
            "侧边栏节点重建时未跟随新位置"
        )
        try expect(
            continuity.decision(
                for: .temporarilyUnavailable(trailingEdgeX: nil),
                timestamp: 2.2
            ) == .visible(trailingEdgeX: 430),
            "短暂无法取得几何时组件消失"
        )
        try expect(
            continuity.decision(
                for: .nonTask(trailingEdgeX: 474),
                timestamp: 3
            ) == .visible(trailingEdgeX: 474),
            "持续拖动侧边栏时组件消失"
        )
        try expect(
            continuity.decision(
                for: .task(trailingEdgeX: 474),
                timestamp: 3.1
            ) == .visible(trailingEdgeX: 474),
            "拖动结束后任务页未恢复确认"
        )
        try expect(
            continuity.decision(
                for: .nonTask(trailingEdgeX: 474),
                timestamp: 5
            ) == .visible(trailingEdgeX: 474),
            "单次非任务页观察不应立即隐藏"
        )
        try expect(
            continuity.decision(
                for: .nonTask(trailingEdgeX: 474),
                timestamp: 5.25
            ) == .hidden,
            "连续确认非任务页后组件没有隐藏"
        )
        try expect(
            continuity.decision(
                for: .temporarilyUnavailable(trailingEdgeX: 500),
                timestamp: 5.5
            ) == .hidden,
            "隐藏后临时不可用状态错误恢复了组件"
        )
        try expect(
            continuity.decision(
                for: .task(trailingEdgeX: 414),
                timestamp: 6
            ) == .visible(trailingEdgeX: 414),
            "回到任务页后组件没有恢复"
        )
        try expect(
            continuity.decision(
                for: .sidebarHidden,
                timestamp: 6.1
            ) == .hidden,
            "侧边栏收起后组件没有立即隐藏"
        )
    }

    private static func launchAtLoginCoordination() throws {
        let enabledService = FakeLaunchAtLoginService(status: .enabled)
        let enabledCoordinator = LaunchAtLoginCoordinator()
        try expect(
            enabledCoordinator.ensureEnabled(using: enabledService) == .alreadyEnabled,
            "已启用登录项时返回结果错误"
        )
        try expect(
            enabledService.registrationCount == 0,
            "已启用登录项仍重复注册"
        )

        let newService = FakeLaunchAtLoginService(status: .notRegistered)
        let newCoordinator = LaunchAtLoginCoordinator()
        try expect(
            newCoordinator.ensureEnabled(using: newService) == .registrationRequested,
            "未注册登录项时没有请求注册"
        )
        try expect(newService.registrationCount == 1, "登录项注册次数错误")
        try expect(
            newCoordinator.ensureEnabled(using: newService) == .alreadyHandled,
            "重复确保登录项时结果错误"
        )
        try expect(newService.registrationCount == 1, "登录项被重复注册")

        let approvalService = FakeLaunchAtLoginService(status: .requiresApproval)
        try expect(
            LaunchAtLoginCoordinator().ensureEnabled(using: approvalService)
                == .requiresApproval,
            "需要用户批准的状态被误处理"
        )
        try expect(approvalService.registrationCount == 0, "需要批准时仍尝试注册")

        let unavailableService = FakeLaunchAtLoginService(status: .unavailable)
        try expect(
            LaunchAtLoginCoordinator().ensureEnabled(using: unavailableService)
                == .unavailable,
            "不可用登录项状态被误处理"
        )

        let failingService = FakeLaunchAtLoginService(status: .notRegistered)
        failingService.shouldFail = true
        try expect(
            LaunchAtLoginCoordinator().ensureEnabled(using: failingService) == .failed,
            "登录项注册失败未被安全降级"
        )
    }

    private static func shortJSONLineDelivery() throws {
        let pipe = Pipe()
        let closeWorkItem = DispatchWorkItem {
            try? pipe.fileHandleForWriting.close()
        }
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + 0.8,
            execute: closeWorkItem
        )

        try pipe.fileHandleForWriting.write(
            contentsOf: Data("{\"id\":1,\"result\":{}}\n".utf8)
        )

        var reader = JSONLineReader(handle: pipe.fileHandleForReading)
        let startedAt = Date()
        let envelopes = try reader.readEnvelopes(untilResponseFor: 1)
        let elapsed = Date().timeIntervalSince(startedAt)

        closeWorkItem.cancel()
        try? pipe.fileHandleForWriting.close()
        try expect(envelopes.count == 1, "未读取到短 JSON 行")
        try expect(elapsed < 0.5, "读取等待了管道关闭，无法用于长连接")
    }

    private static func expect(
        _ condition: @autoclosure () throws -> Bool,
        _ message: String
    ) throws {
        if try !condition() {
            throw CheckFailure(description: message)
        }
    }

    private static func require<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else {
            throw CheckFailure(description: message)
        }
        return value
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
