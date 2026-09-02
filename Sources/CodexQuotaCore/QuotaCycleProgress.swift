import Foundation

public enum QuotaExhaustionForecast: Equatable, Sendable {
    case estimated(Date)
    case afterReset
    case unavailable
}

public enum QuotaUsageDeviationBand: Equatable, Sendable {
    case within25
    case over25
    case over50
}

public struct QuotaUsageDeviation: Equatable, Sendable {
    public let signedPercentagePoints: Double

    public init(signedPercentagePoints: Double) {
        self.signedPercentagePoints = signedPercentagePoints
    }

    public var band: QuotaUsageDeviationBand {
        let magnitude = abs(signedPercentagePoints)
        let boundaryTolerance = 1e-9
        if magnitude > 50 + boundaryTolerance { return .over50 }
        if magnitude > 25 + boundaryTolerance { return .over25 }
        return .within25
    }
}

public struct QuotaCycleProgress: Equatable, Sendable {
    public let timeElapsedFraction: Double
    public let quotaUsedFraction: Double
    public let exhaustionForecast: QuotaExhaustionForecast

    public var timeElapsedPercent: Int {
        Int((timeElapsedFraction * 100).rounded())
    }

    public var quotaUsedPercent: Int {
        Int((quotaUsedFraction * 100).rounded())
    }

    public var usageDeviation: QuotaUsageDeviation {
        QuotaUsageDeviation(
            signedPercentagePoints: (quotaUsedFraction - timeElapsedFraction) * 100
        )
    }

    public static func calculate(for status: QuotaStatus) -> QuotaCycleProgress? {
        guard let remainingPercent = status.remainingPercent,
              let resetsAt = status.resetsAt,
              let windowDurationMins = status.windowDurationMins,
              windowDurationMins > 0,
              resetsAt > status.fetchedAt else {
            return nil
        }

        let windowDuration = Double(windowDurationMins) * 60
        let timeRemaining = resetsAt.timeIntervalSince(status.fetchedAt)
        guard timeRemaining <= windowDuration else { return nil }
        let timeElapsedFraction = clamp(1 - timeRemaining / windowDuration)
        let quotaUsedFraction = clamp(1 - Double(remainingPercent) / 100)
        let exhaustionForecast = forecast(
            resetsAt: resetsAt,
            windowDuration: windowDuration,
            timeElapsedFraction: timeElapsedFraction,
            quotaUsedFraction: quotaUsedFraction
        )

        return QuotaCycleProgress(
            timeElapsedFraction: timeElapsedFraction,
            quotaUsedFraction: quotaUsedFraction,
            exhaustionForecast: exhaustionForecast
        )
    }

    private static func forecast(
        resetsAt: Date,
        windowDuration: TimeInterval,
        timeElapsedFraction: Double,
        quotaUsedFraction: Double
    ) -> QuotaExhaustionForecast {
        guard timeElapsedFraction > 0, quotaUsedFraction > 0 else {
            return .unavailable
        }

        let windowStart = resetsAt.addingTimeInterval(-windowDuration)
        let elapsedDuration = windowDuration * timeElapsedFraction
        let estimatedAt = windowStart.addingTimeInterval(
            elapsedDuration / quotaUsedFraction
        )
        guard estimatedAt <= resetsAt else {
            return .afterReset
        }

        return .estimated(
            Date(timeIntervalSince1970: estimatedAt.timeIntervalSince1970.rounded())
        )
    }

    private static func clamp(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}
