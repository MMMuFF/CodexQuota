import Foundation

public struct ResetCreditActionState: Equatable, Sendable {
    public let title: String
    public let isEnabled: Bool

    public init(title: String, isEnabled: Bool) {
        self.title = title
        self.isEnabled = isEnabled
    }
}

public enum QuotaDisplayFormatter {
    public static func mainTitle(
        for status: QuotaStatus,
        timeZone: TimeZone = TimeZone(identifier: "Asia/Shanghai")!
    ) -> String {
        let percent = status.remainingPercent.map { "\($0)%" } ?? "--"
        guard let resetsAt = status.resetsAt else {
            return percent
        }

        let days = remainingCalendarDays(
            until: resetsAt,
            from: status.fetchedAt,
            timeZone: timeZone
        )
        return "\(percent) · \(monthDay(resetsAt, timeZone: timeZone)) · \(days)天"
    }

    public static func title(
        for status: QuotaStatus,
        timeZone: TimeZone = TimeZone(identifier: "Asia/Shanghai")!
    ) -> String {
        mainTitle(for: status, timeZone: timeZone)
    }

    public static func hoverTitle(
        for status: QuotaStatus,
        timeZone: TimeZone = TimeZone(identifier: "Asia/Shanghai")!
    ) -> String {
        let percent = status.remainingPercent.map { "\($0)%" } ?? "--"
        guard let resetsAt = status.resetsAt else {
            return percent
        }

        let days = remainingCalendarDays(
            until: resetsAt,
            from: status.fetchedAt,
            timeZone: timeZone
        )
        return "\(percent) · \(monthDayTime(resetsAt, timeZone: timeZone)) · \(days)天"
    }

    public static func tooltip(
        for status: QuotaStatus,
        timeZone: TimeZone = TimeZone(identifier: "Asia/Shanghai")!
    ) -> String {
        var lines = [hoverTitle(for: status, timeZone: timeZone)]

        if status.subscriptionActiveUntil != nil {
            lines.append(subscriptionExpirationText(for: status, timeZone: timeZone))
        }

        lines.append(resetCreditDetailText(for: status, timeZone: timeZone))

        return lines.joined(separator: "\n")
    }

    public static func resetCreditDetailText(
        for status: QuotaStatus,
        timeZone: TimeZone = TimeZone(identifier: "Asia/Shanghai")!
    ) -> String {
        if let expiresAt = status.nearestResetCreditExpiresAt {
            let days = remainingCalendarDays(
                until: expiresAt,
                from: status.fetchedAt,
                timeZone: timeZone
            )
            return "最早到期券：\(monthDayTime(expiresAt, timeZone: timeZone)) · \(days)天"
        }

        guard let availableCount = status.resetCreditsAvailableCount else {
            return "重置券：暂不可用"
        }
        return availableCount > 0
            ? "重置券：\(availableCount) 张可用（到期时间暂不可用）"
            : "重置券：暂无"
    }

    public static func resetCreditActionState(
        availableCount: Int?
    ) -> ResetCreditActionState {
        guard let availableCount else {
            return ResetCreditActionState(title: "重置券暂不可用", isEnabled: false)
        }
        guard availableCount > 0 else {
            return ResetCreditActionState(title: "暂无重置券", isEnabled: false)
        }
        return ResetCreditActionState(
            title: "使用重置券（\(availableCount)）",
            isEnabled: true
        )
    }

    public static func freshnessText(for status: QuotaStatus) -> String {
        if hasUnavailablePaidSubscriptionExpiration(status) {
            return "会员到期时间暂不可用，主额度已更新"
        }
        guard let warning = status.warnings.first else { return "刚刚更新" }
        return "\(warning)，主额度已更新"
    }

    public static func subscriptionExpirationText(
        for status: QuotaStatus,
        timeZone: TimeZone = TimeZone(identifier: "Asia/Shanghai")!
    ) -> String {
        guard let plan = paidPlanDisplayName(status.planType) else {
            return "会员到期：暂不可用"
        }
        guard let activeUntil = status.subscriptionActiveUntil else {
            return "\(plan) 到期：暂不可用"
        }
        guard !hasUnavailablePaidSubscriptionExpiration(status) else {
            return "\(plan) 到期：暂不可用"
        }

        let days = remainingCalendarDays(
            until: activeUntil,
            from: status.fetchedAt,
            timeZone: timeZone
        )
        return "\(plan) 到期：\(monthDay(activeUntil, timeZone: timeZone)) · \(days)天"
    }

    public static func remainingCalendarDays(
        until date: Date,
        from referenceDate: Date,
        timeZone: TimeZone = TimeZone(identifier: "Asia/Shanghai")!
    ) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let referenceDay = calendar.startOfDay(for: referenceDate)
        let targetDay = calendar.startOfDay(for: date)
        return max(
            0,
            calendar.dateComponents([.day], from: referenceDay, to: targetDay).day ?? 0
        )
    }

    private static func paidPlanDisplayName(_ planType: String?) -> String? {
        SubscriptionPlan.paidDisplayName(planType)
    }

    private static func hasUnavailablePaidSubscriptionExpiration(_ status: QuotaStatus) -> Bool {
        guard paidPlanDisplayName(status.planType) != nil else { return false }
        guard let activeUntil = status.subscriptionActiveUntil else { return false }
        // OAuth refresh can preserve an older ID Token after a subscription renewal.
        return activeUntil <= status.fetchedAt
    }

    private static func monthDay(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = timeZone
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }

    private static func monthDayTime(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = timeZone
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: date)
    }
}
