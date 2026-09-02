import CryptoKit
import Foundation

public struct PendingResetCreditRequest: Codable, Equatable, Sendable {
    public static let defaultMaximumAge: TimeInterval = 24 * 60 * 60

    public let accountFingerprint: String
    public let idempotencyKey: UUID
    public let createdAt: Date

    public init(
        accountFingerprint: String,
        idempotencyKey: UUID,
        createdAt: Date
    ) {
        self.accountFingerprint = accountFingerprint
        self.idempotencyKey = idempotencyKey
        self.createdAt = createdAt
    }

    public func isReusable(
        for accountFingerprint: String,
        now: Date,
        maximumAge: TimeInterval = defaultMaximumAge
    ) -> Bool {
        self.accountFingerprint == accountFingerprint
            && now >= createdAt
            && now.timeIntervalSince(createdAt) <= maximumAge
    }
}

enum AccountIdentityParser {
    static func fingerprint(authAccountID: String?) -> String? {
        let normalizedAccountID = authAccountID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalizedAccountID, !normalizedAccountID.isEmpty else {
            return nil
        }

        let digest = SHA256.hash(
            data: Data("account:\(normalizedAccountID)".utf8)
        )
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

enum ResetCreditAccountGuard {
    static func validate(
        expectedFingerprint: String,
        currentFingerprint: String?
    ) throws {
        guard currentFingerprint == expectedFingerprint else {
            throw QuotaServiceError.accountChanged
        }
    }
}

enum AccountIdentityGuard {
    static func validateUnchanged(
        initial: String?,
        current: String?
    ) throws {
        guard initial == current else {
            throw QuotaServiceError.accountChanged
        }
    }
}

enum ResetCreditRedirectPolicy {
    static func redirectedRequest(_ request: URLRequest) -> URLRequest? {
        nil
    }
}

enum SubscriptionRedirectPolicy {
    static func redirectedRequest(_ request: URLRequest) -> URLRequest? {
        nil
    }
}
