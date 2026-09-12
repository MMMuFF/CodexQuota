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
    case resetCreditExpired

    public var errorDescription: String? {
        switch self {
        case .codexExecutableNotFound:
            return L("未找到 Codex 可执行文件", "Codex executable not found")
        case .codexLaunchFailed:
            return L("无法启动 Codex app-server", "Could not start Codex app-server")
        case .appServerTimedOut:
            return L("Codex app-server 响应超时", "Codex app-server timed out")
        case let .codexExited(status):
            return L("Codex app-server 异常退出（\(status)）", "Codex app-server exited unexpectedly (\(status))")
        case .malformedAppServerResponse:
            return L("Codex app-server 返回了无法识别的数据", "Unrecognized data from Codex app-server")
        case let .appServerRequestFailed(message):
            return L("Codex app-server 请求失败：\(message)", "Codex app-server request failed: \(message)")
        case .unsupportedResetCreditOutcome:
            return L("Codex 返回了未知的重置券结果", "Unknown reset credit result from Codex")
        case .accountChanged:
            return L("Codex 账户已切换，未使用重置券", "Codex account changed; no credit used")
        case .resetCreditExpired:
            return L("临期重置券已过期，已取消自动使用", "Reset credit expired; automatic use cancelled")
        }
    }
}
