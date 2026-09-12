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
        timeZone: TimeZone = .autoupdatingCurrent
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
        return L("\(percent) · \(monthDay(resetsAt, timeZone: timeZone)) · \(days)天", "\(percent) · \(monthDay(resetsAt, timeZone: timeZone)) · \(days)d")
    }

    public static func title(
        for status: QuotaStatus,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        mainTitle(for: status, timeZone: timeZone)
    }

    public static func hoverTitle(
        for status: QuotaStatus,
        timeZone: TimeZone = .autoupdatingCurrent
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
        return L("\(percent) · \(monthDayTime(resetsAt, timeZone: timeZone)) · \(days)天", "\(percent) · \(monthDayTime(resetsAt, timeZone: timeZone)) · \(days)d")
    }

    public static func tooltip(
        for status: QuotaStatus,
        timeZone: TimeZone = .autoupdatingCurrent
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
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        if let expiresAt = status.nearestResetCreditExpiresAt {
            let days = remainingCalendarDays(
                until: expiresAt,
                from: status.fetchedAt,
                timeZone: timeZone
            )
            return L("最早到期券：\(monthDayTime(expiresAt, timeZone: timeZone)) · \(days)天", "Earliest credit: \(monthDayTime(expiresAt, timeZone: timeZone)) · \(days)d")
        }

        guard let availableCount = status.resetCreditsAvailableCount else {
            return L("重置券：暂不可用", "Reset credits: unavailable")
        }
        return availableCount > 0
            ? L("重置券：\(availableCount) 张可用（到期时间暂不可用）", "Reset credits: \(availableCount) available (expiry unavailable)")
            : L("重置券：暂无", "Reset credits: none")
    }

    public static func resetCreditActionState(
        availableCount: Int?
    ) -> ResetCreditActionState {
        guard let availableCount else {
            return ResetCreditActionState(title: L("重置券暂不可用", "Credits unavailable"), isEnabled: false)
        }
        guard availableCount > 0 else {
            return ResetCreditActionState(title: L("暂无重置券", "No reset credits"), isEnabled: false)
        }
        return ResetCreditActionState(
            title: L("使用重置券（\(availableCount)）", "Use reset credit (\(availableCount))"),
            isEnabled: true
        )
    }

    public static func freshnessText(for status: QuotaStatus) -> String {
        if hasUnavailablePaidSubscriptionExpiration(status) {
            return L("会员到期时间暂不可用，主额度已更新", "Membership expiry unavailable; quota updated")
        }
        guard let warning = status.warnings.first else { return L("刚刚更新", "Just updated") }
        return L("\(warning)，主额度已更新", "\(warning); quota updated")
    }

    public static func exhaustionForecastText(
        for status: QuotaStatus,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        guard let progress = QuotaCycleProgress.calculate(for: status) else {
            return L("按周期均速，暂无法估算", "Not enough data to estimate")
        }

        switch progress.exhaustionForecast {
        case let .estimated(date):
            return L("按周期均速，预计 \(monthDayTime(date, timeZone: timeZone)) 用完", "At this pace, runs out \(monthDayTime(date, timeZone: timeZone))")
        case .afterReset:
            return L("按周期均速，本轮预计用不完", "At this pace, lasts until reset")
        case .unavailable:
            return L("按周期均速，暂无法估算", "Not enough data to estimate")
        }
    }

    public static func usageDeviationAccessibilityText(
        _ deviation: QuotaUsageDeviation
    ) -> String {
        let roundedMagnitude = Int(abs(deviation.signedPercentagePoints).rounded())
        guard roundedMagnitude > 0 else {
            return L("额度消耗与时间进度一致", "Usage matches elapsed time")
        }
        let direction = deviation.signedPercentagePoints > 0 ? L("快", "ahead") : L("慢", "behind")
        return L("额度消耗比时间进度\(direction) \(roundedMagnitude) 个百分点", "Usage is \(roundedMagnitude) percentage points \(direction) of elapsed time")
    }

    public static func subscriptionExpirationText(
        for status: QuotaStatus,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        guard let plan = paidPlanDisplayName(status.planType) else {
            return L("会员到期：暂不可用", "Membership expires: unavailable")
        }
        guard let activeUntil = status.subscriptionActiveUntil else {
            return L("\(plan) 到期：暂不可用", "\(plan) expires: unavailable")
        }
        guard !hasUnavailablePaidSubscriptionExpiration(status) else {
            return L("\(plan) 到期：暂不可用", "\(plan) expires: unavailable")
        }

        let days = remainingCalendarDays(
            until: activeUntil,
            from: status.fetchedAt,
            timeZone: timeZone
        )
        return L("\(plan) 到期：\(monthDay(activeUntil, timeZone: timeZone)) · \(days)天", "\(plan) expires: \(monthDay(activeUntil, timeZone: timeZone)) · \(days)d")
    }

    public static func remainingCalendarDays(
        until date: Date,
        from referenceDate: Date,
        timeZone: TimeZone = .autoupdatingCurrent
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
        formatter.locale = Locale(identifier: L("zh_CN", "en_US_POSIX"))
        formatter.timeZone = timeZone
        formatter.dateFormat = L("M月d日", "MMM d")
        return formatter.string(from: date)
    }

    private static func monthDayTime(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: L("zh_CN", "en_US_POSIX"))
        formatter.timeZone = timeZone
        formatter.dateFormat = L("M月d日 HH:mm", "MMM d HH:mm")
        return formatter.string(from: date)
    }
}
