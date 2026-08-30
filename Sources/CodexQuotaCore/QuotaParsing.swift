import Foundation

typealias JSONDictionary = [String: Any]

enum JSONValue {
    static func dictionary(_ value: Any?) -> JSONDictionary? {
        value as? JSONDictionary
    }

    static func array(_ value: Any?) -> [Any]? {
        value as? [Any]
    }

    static func value(in dictionary: JSONDictionary, keys: [String]) -> Any? {
        for key in keys where dictionary[key] != nil {
            return dictionary[key]
        }
        return nil
    }

    static func string(_ value: Any?) -> String? {
        if let string = value as? String, !string.isEmpty {
            return string
        }
        return nil
    }

    static func int(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber:
            return number.intValue
        case let string as String:
            return Int(string)
        default:
            return nil
        }
    }

    static func bool(_ value: Any?) -> Bool? {
        switch value {
        case let bool as Bool:
            return bool
        case let number as NSNumber:
            return number.boolValue
        case let string as String:
            return ["true", "1", "yes"].contains(string.lowercased())
        default:
            return nil
        }
    }

    static func date(_ value: Any?) -> Date? {
        if let number = value as? NSNumber {
            return date(fromNumericTimestamp: number.doubleValue)
        }
        if let string = value as? String {
            if let seconds = Double(string) {
                return date(fromNumericTimestamp: seconds)
            }

            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: string) {
                return date
            }

            let standard = ISO8601DateFormatter()
            standard.formatOptions = [.withInternetDateTime]
            return standard.date(from: string)
        }
        return nil
    }

    private static func date(fromNumericTimestamp timestamp: Double) -> Date {
        let seconds = timestamp > 10_000_000_000 ? timestamp / 1_000 : timestamp
        return Date(timeIntervalSince1970: seconds)
    }
}

struct ParsedQuotaSnapshot {
    let remainingPercent: Int?
    let resetsAt: Date?
    let windowDurationMins: Int?
    let planType: String?
    let resetCreditsAvailableCount: Int?
    let nearestResetCreditExpiresAt: Date?
    let hasResetCreditDetails: Bool
}

enum RateLimitParser {
    static func parse(
        accountResult: Any?,
        rateLimitResult: Any
    ) throws -> ParsedQuotaSnapshot {
        guard let root = JSONValue.dictionary(rateLimitResult) else {
            throw QuotaServiceError.malformedAppServerResponse
        }

        let snapshot = codexSnapshot(in: root) ?? root
        let selectedWindow = longestWindow(in: snapshot)
        let usedPercent = selectedWindow.flatMap {
            JSONValue.int(JSONValue.value(in: $0, keys: ["usedPercent", "used_percent"]))
        }
        let remainingPercent = usedPercent.map { min(100, max(0, 100 - $0)) }
        let resetsAt = selectedWindow.flatMap {
            JSONValue.date(JSONValue.value(in: $0, keys: ["resetsAt", "resets_at"]))
        }
        let duration = selectedWindow.flatMap {
            JSONValue.int(JSONValue.value(in: $0, keys: ["windowDurationMins", "window_duration_mins"]))
        }

        let accountPlan = JSONValue.dictionary(accountResult)
            .flatMap { JSONValue.dictionary($0["account"]) }
            .flatMap { JSONValue.string(JSONValue.value(in: $0, keys: ["planType", "plan_type"])) }
        let plan = JSONValue.string(JSONValue.value(in: snapshot, keys: ["planType", "plan_type"]))
            ?? accountPlan

        let resetSummary = ResetCreditParser.parseAppServerSummary(
            JSONValue.value(in: root, keys: ["rateLimitResetCredits", "rate_limit_reset_credits"])
        )

        return ParsedQuotaSnapshot(
            remainingPercent: remainingPercent,
            resetsAt: resetsAt,
            windowDurationMins: duration,
            planType: plan,
            resetCreditsAvailableCount: resetSummary.availableCount,
            nearestResetCreditExpiresAt: resetSummary.nearestExpiresAt,
            hasResetCreditDetails: resetSummary.hasDetails
        )
    }

    private static func codexSnapshot(in root: JSONDictionary) -> JSONDictionary? {
        if let byLimitID = JSONValue.dictionary(
            JSONValue.value(in: root, keys: ["rateLimitsByLimitId", "rate_limits_by_limit_id"])
        ) {
            if let exact = JSONValue.dictionary(byLimitID["codex"]) {
                return exact
            }
            if let match = byLimitID.first(where: { $0.key.lowercased() == "codex" }),
               let dictionary = JSONValue.dictionary(match.value) {
                return dictionary
            }
        }

        return JSONValue.dictionary(
            JSONValue.value(in: root, keys: ["rateLimits", "rate_limits"])
        )
    }

    private static func longestWindow(in snapshot: JSONDictionary) -> JSONDictionary? {
        var windows = ["primary", "secondary"].compactMap {
            JSONValue.dictionary(snapshot[$0])
        }
        if let additional = JSONValue.array(snapshot["windows"]) {
            windows.append(contentsOf: additional.compactMap(JSONValue.dictionary))
        }

        return windows.enumerated().max { lhs, rhs in
            let lhsDuration = JSONValue.int(
                JSONValue.value(in: lhs.element, keys: ["windowDurationMins", "window_duration_mins"])
            ) ?? -1
            let rhsDuration = JSONValue.int(
                JSONValue.value(in: rhs.element, keys: ["windowDurationMins", "window_duration_mins"])
            ) ?? -1
            if lhsDuration == rhsDuration {
                return lhs.offset > rhs.offset
            }
            return lhsDuration < rhsDuration
        }?.element
    }
}

struct ParsedResetCreditSummary {
    let availableCount: Int?
    let nearestExpiresAt: Date?
    let hasDetails: Bool
}

struct ParsedSubscriptionSummary {
    let activeUntil: Date?
    let planType: String?
    let willRenew: Bool?
}

struct ResolvedSubscriptionStatus {
    let planType: String?
    let activeUntil: Date?
}

enum SubscriptionPlan {
    static func paidDisplayName(_ planType: String?) -> String? {
        switch planType?.lowercased() {
        case "pro":
            return "Pro"
        case "prolite", "pro_lite":
            return "Pro Lite"
        case "plus":
            return "Plus"
        case "team":
            return "Team"
        case "business", "self_serve_business_usage_based":
            return "Business"
        case "enterprise", "enterprise_cbp_usage_based":
            return "Enterprise"
        default:
            return nil
        }
    }
}

enum SubscriptionStatusResolver {
    static func resolve(
        appServerPlanType: String?,
        tokenPlanType: String?,
        tokenActiveUntil: Date?,
        live: ParsedSubscriptionSummary?
    ) -> ResolvedSubscriptionStatus {
        if let live {
            let planType = live.planType ?? appServerPlanType ?? tokenPlanType
            return ResolvedSubscriptionStatus(
                planType: planType,
                activeUntil: SubscriptionPlan.paidDisplayName(planType) == nil
                    ? nil
                    : live.activeUntil
            )
        }
        let planType = appServerPlanType ?? tokenPlanType
        return ResolvedSubscriptionStatus(
            planType: planType,
            activeUntil: SubscriptionPlan.paidDisplayName(planType) == nil
                ? nil
                : tokenActiveUntil
        )
    }
}

enum SubscriptionParser {
    static func parseHTTPResponse(_ data: Data) throws -> ParsedSubscriptionSummary {
        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw QuotaServiceError.malformedAppServerResponse
        }
        guard !response.planType.isEmpty else {
            throw QuotaServiceError.malformedAppServerResponse
        }
        let activeUntil = try parseActiveUntil(response.activeUntil)

        return ParsedSubscriptionSummary(
            activeUntil: activeUntil,
            planType: response.planType,
            willRenew: response.willRenew
        )
    }

    private static func parseActiveUntil(_ value: String?) throws -> Date? {
        guard let value else { return nil }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        guard let date = standard.date(from: value) else {
            throw QuotaServiceError.malformedAppServerResponse
        }
        return date
    }

    private struct Response: Decodable {
        let activeUntil: String?
        let planType: String
        let willRenew: Bool?

        private enum CodingKeys: String, CodingKey {
            case activeUntil = "active_until"
            case planType = "plan_type"
            case willRenew = "will_renew"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            guard container.contains(.activeUntil) else {
                throw DecodingError.keyNotFound(
                    CodingKeys.activeUntil,
                    DecodingError.Context(
                        codingPath: container.codingPath,
                        debugDescription: "Missing active_until"
                    )
                )
            }
            activeUntil = try container.decodeIfPresent(String.self, forKey: .activeUntil)
            planType = try container.decode(String.self, forKey: .planType)
            willRenew = try container.decodeIfPresent(Bool.self, forKey: .willRenew)
        }
    }
}

enum ResetCreditParser {
    static func parseAppServerSummary(_ value: Any?) -> ParsedResetCreditSummary {
        guard let summary = JSONValue.dictionary(value) else {
            return ParsedResetCreditSummary(
                availableCount: nil,
                nearestExpiresAt: nil,
                hasDetails: false
            )
        }

        let availableCount = JSONValue.int(
            JSONValue.value(in: summary, keys: ["availableCount", "available_count"])
        )
        guard let credits = JSONValue.array(summary["credits"]) else {
            return ParsedResetCreditSummary(
                availableCount: availableCount,
                nearestExpiresAt: nil,
                hasDetails: false
            )
        }

        return ParsedResetCreditSummary(
            availableCount: availableCount,
            nearestExpiresAt: nearestAvailableExpiration(in: credits),
            hasDetails: true
        )
    }

    static func parseHTTPResponse(_ data: Data) throws -> ParsedResetCreditSummary {
        let json = try JSONSerialization.jsonObject(with: data)
        let availableCount = findFirstInt(
            in: json,
            keys: ["availableCount", "available_count", "availableCredits", "available_credits"]
        )
        let creditArrays = findCreditArrays(in: json)
        let creditObjects = creditArrays.flatMap { $0 }
        let availableObjects = creditObjects.filter(isAvailableCredit)

        return ParsedResetCreditSummary(
            availableCount: availableCount ?? (creditArrays.isEmpty ? nil : availableObjects.count),
            nearestExpiresAt: nearestAvailableExpiration(in: creditObjects),
            hasDetails: !creditObjects.isEmpty
        )
    }

    private static func nearestAvailableExpiration(in credits: [Any]) -> Date? {
        credits
            .compactMap(JSONValue.dictionary)
            .filter(isAvailableCredit)
            .compactMap {
                JSONValue.date(
                    JSONValue.value(
                        in: $0,
                        keys: ["expiresAt", "expires_at", "expiration", "expiration_time"]
                    )
                )
            }
            .min()
    }

    private static func isAvailableCredit(_ value: Any) -> Bool {
        guard let credit = JSONValue.dictionary(value) else {
            return false
        }
        if let status = JSONValue.string(
            JSONValue.value(in: credit, keys: ["status", "state"])
        ) {
            return status.lowercased() == "available"
        }
        if let available = JSONValue.bool(
            JSONValue.value(in: credit, keys: ["available", "isAvailable", "is_available"])
        ) {
            return available
        }
        return true
    }

    private static func findCreditArrays(in value: Any) -> [[Any]] {
        if let dictionary = JSONValue.dictionary(value) {
            var matches: [[Any]] = []
            for (key, nested) in dictionary {
                let normalized = key.lowercased().replacingOccurrences(of: "_", with: "")
                if ["credits", "resetcredits", "ratelimitresetcredits", "items"].contains(normalized),
                   let array = JSONValue.array(nested) {
                    matches.append(array)
                } else {
                    matches.append(contentsOf: findCreditArrays(in: nested))
                }
            }
            return matches
        }
        if let array = JSONValue.array(value) {
            return array.flatMap(findCreditArrays)
        }
        return []
    }

    private static func findFirstInt(in value: Any, keys: Set<String>) -> Int? {
        if let dictionary = JSONValue.dictionary(value) {
            for key in keys {
                if let integer = JSONValue.int(dictionary[key]) {
                    return integer
                }
            }
            for nested in dictionary.values {
                if let integer = findFirstInt(in: nested, keys: keys) {
                    return integer
                }
            }
        } else if let array = JSONValue.array(value) {
            for nested in array {
                if let integer = findFirstInt(in: nested, keys: keys) {
                    return integer
                }
            }
        }
        return nil
    }
}

enum JWTClaimParser {
    static func subscriptionActiveUntil(from token: String) -> Date? {
        guard let claims = authClaims(from: token) else {
            return nil
        }
        return JSONValue.date(
            JSONValue.value(
                in: claims,
                keys: ["chatgpt_subscription_active_until", "subscription_active_until"]
            )
        )
    }

    static func accountID(from token: String) -> String? {
        authClaims(from: token).flatMap {
            JSONValue.string(
                JSONValue.value(in: $0, keys: ["chatgpt_account_id", "account_id"])
            )
        }
    }

    static func planType(from token: String) -> String? {
        authClaims(from: token).flatMap {
            JSONValue.string(
                JSONValue.value(in: $0, keys: ["chatgpt_plan_type", "plan_type"])
            )
        }
    }

    private static func authClaims(from token: String) -> JSONDictionary? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2,
              let payload = base64URLDecode(String(parts[1])),
              let root = try? JSONSerialization.jsonObject(with: payload) as? JSONDictionary else {
            return nil
        }
        return JSONValue.dictionary(root["https://api.openai.com/auth"]) ?? root
    }

    private static func base64URLDecode(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        return Data(base64Encoded: base64)
    }
}

enum ResetCreditConsumeParser {
    static func parse(_ value: Any) throws -> ResetCreditConsumeResult {
        guard let dictionary = JSONValue.dictionary(value),
              let rawOutcome = JSONValue.string(dictionary["outcome"]),
              let result = ResetCreditConsumeResult(rawValue: rawOutcome) else {
            throw QuotaServiceError.unsupportedResetCreditOutcome
        }
        return result
    }
}
