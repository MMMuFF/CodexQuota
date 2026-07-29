import Foundation

public struct QuotaStatus: Equatable, Sendable {
    public let remainingPercent: Int?
    public let resetsAt: Date?
    public let windowDurationMins: Int?
    public let planType: String?
    public let subscriptionActiveUntil: Date?
    public let resetCreditsAvailableCount: Int?
    public let nearestResetCreditExpiresAt: Date?
    public let fetchedAt: Date
    public let warnings: [String]
    public let accountFingerprint: String?

    public init(
        remainingPercent: Int?,
        resetsAt: Date?,
        windowDurationMins: Int?,
        planType: String?,
        subscriptionActiveUntil: Date?,
        resetCreditsAvailableCount: Int?,
        nearestResetCreditExpiresAt: Date?,
        fetchedAt: Date,
        warnings: [String],
        accountFingerprint: String? = nil
    ) {
        self.remainingPercent = remainingPercent
        self.resetsAt = resetsAt
        self.windowDurationMins = windowDurationMins
        self.planType = planType
        self.subscriptionActiveUntil = subscriptionActiveUntil
        self.resetCreditsAvailableCount = resetCreditsAvailableCount
        self.nearestResetCreditExpiresAt = nearestResetCreditExpiresAt
        self.fetchedAt = fetchedAt
        self.warnings = warnings
        self.accountFingerprint = accountFingerprint
    }
}

public enum ResetCreditConsumeResult: String, Equatable, Sendable {
    case reset
    case nothingToReset
    case noCredit
    case alreadyRedeemed

    public var succeeded: Bool {
        self == .reset || self == .alreadyRedeemed
    }

    public var remainingCount: Int? {
        nil
    }
}

public enum QuotaServiceError: Error, LocalizedError, Equatable, Sendable {
    case codexExecutableNotFound
    case codexLaunchFailed
    case appServerTimedOut
    case codexExited(Int32)
    case malformedAppServerResponse
    case appServerRequestFailed(String)
    case unsupportedResetCreditOutcome
    case accountChanged

    public var errorDescription: String? {
        switch self {
        case .codexExecutableNotFound:
            return "未找到 Codex 可执行文件"
        case .codexLaunchFailed:
            return "无法启动 Codex app-server"
        case .appServerTimedOut:
            return "Codex app-server 响应超时"
        case let .codexExited(status):
            return "Codex app-server 异常退出（\(status)）"
        case .malformedAppServerResponse:
            return "Codex app-server 返回了无法识别的数据"
        case let .appServerRequestFailed(message):
            return "Codex app-server 请求失败：\(message)"
        case .unsupportedResetCreditOutcome:
            return "Codex 返回了未知的重置券结果"
        case .accountChanged:
            return "Codex 账户已切换，未使用重置券"
        }
    }
}
