import Foundation

public enum AutomaticResetCreditPolicy {
    public static let expiryWindow: TimeInterval = 30 * 60
    public static let checkInterval: TimeInterval = 60

    public static func canSend(deadline: Date?, now: Date) -> Bool {
        deadline.map { $0 > now } ?? true
    }

    public static func expiringCredit(
        in status: QuotaStatus,
        enabled: Bool,
        now: Date
    ) -> Date? {
        guard enabled,
              let account = status.accountFingerprint, !account.isEmpty,
              (status.resetCreditsAvailableCount ?? 0) > 0,
              now >= status.fetchedAt,
              now.timeIntervalSince(status.fetchedAt) <= checkInterval,
              let expiration = status.nearestResetCreditExpiresAt,
              expiration > now,
              expiration.timeIntervalSince(now) <= expiryWindow else { return nil }
        return expiration
    }
}

public final class AutomaticResetCreditAutomation {
    private static let defaultsKey = "com.mufeng.codexquota.automatic-reset-v1"
    private let defaults: UserDefaults
    private struct State: Codable {
        var enabledAccounts: Set<String> = []
        var attempts: [String: Attempt] = [:]
    }
    private struct Attempt: Codable {
        var expiration: Date
        var request: PendingResetCreditRequest?
        var lastAttemptAt: Date
        var completed = false
    }
    private var state: State

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        state = defaults.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode(State.self, from: $0) } ?? State()
    }

    public func isEnabled(for account: String?) -> Bool {
        guard let account, !account.isEmpty else { return false }
        return state.enabledAccounts.contains(account)
    }

    public func setEnabled(_ enabled: Bool, for account: String) {
        guard !account.isEmpty else { return }
        if enabled {
            state.enabledAccounts.insert(account)
        } else {
            state.enabledAccounts.remove(account)
        }
        persist()
    }

    public func beginAttempt(
        for status: QuotaStatus, now: Date,
        pendingRequest: PendingResetCreditRequest?
    ) -> PendingResetCreditRequest? {
        guard let expiration = AutomaticResetCreditPolicy.expiringCredit(
            in: status, enabled: isEnabled(for: status.accountFingerprint), now: now
        ), let account = status.accountFingerprint else { return nil }

        let previous = state.attempts[account]
        if let previous, previous.completed, previous.expiration == expiration { return nil }
        // An unanswered request must never silently become a new redemption intent.
        if let previous, previous.request != nil, previous.expiration != expiration { return nil }
        if let previous,
           now.timeIntervalSince(previous.lastAttemptAt) < AutomaticResetCreditPolicy.checkInterval {
            return nil
        }
        let request = previous?.request ?? pendingRequest ?? PendingResetCreditRequest(
            accountFingerprint: account, idempotencyKey: UUID(), createdAt: now
        )
        guard request.isReusable(for: account, now: now) else { return nil }
        state.attempts[account] = Attempt(
            expiration: expiration, request: request, lastAttemptAt: now
        )
        persist()
        return request
    }

    public func recordOutcome(
        _ outcome: ResetCreditConsumeResult,
        for request: PendingResetCreditRequest,
        expiration: Date?
    ) {
        let account = request.accountFingerprint
        let previous = state.attempts[account]
        guard previous?.request?.idempotencyKey == request.idempotencyKey || previous?.request == nil,
              let expiration = previous?.request == nil ? expiration : previous?.expiration else { return }
        state.attempts[account] = Attempt(
            expiration: expiration,
            request: nil,
            lastAttemptAt: previous?.lastAttemptAt ?? request.createdAt,
            completed: outcome != .nothingToReset
        )
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
