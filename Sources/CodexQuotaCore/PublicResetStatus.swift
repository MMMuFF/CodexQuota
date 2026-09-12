import Foundation

public struct PublicResetPresentation: Sendable {
    public let title: String
    public let latest: String
    public let detail: String
    public let sourceURL: URL?
}

public struct PublicResetStatus: Decodable, Sendable {
    struct Payload: Decodable, Sendable {
        let scheduledReset: Scheduled?
        let latestReset: Reset?
        let activeWatch: Watch?
    }

    struct Reset: Decodable, Sendable {
        let resetType: Kind
        let announcedAt: Date
        let text: String
        let source: Source
    }

    struct Watch: Decodable, Sendable {
        let resetChancePercent: Int?
        let forecastWindow: String
        let observedAt: Date
        let expiresAt: Date
        let text: String
        let source: Source
    }

    struct Scheduled: Decodable, Sendable {
        enum State: String, Decodable, Sendable { case scheduled }
        let status: State
        let resetType: Kind
        let scheduledFor: Date?
        let announcedAt: Date
        let text: String
        let source: Source
    }

    enum Kind: String, Decodable, Sendable { case regular, banked }

    struct Source: Decodable, Sendable {
        enum Kind: String, Decodable, Sendable { case xPost = "x_post", observed }
        let type: Kind
        let author: String?
        let url: String?

        var safeURL: URL? {
            guard let url, let parts = URLComponents(string: url), parts.scheme == "https",
                  parts.user == nil, parts.password == nil, parts.port == nil, parts.query == nil,
                  parts.fragment == nil else { return nil }
            if type == .xPost, author == "thsottiaux", parts.host == "x.com",
               parts.path.range(of: #"^/thsottiaux/status/[0-9]+$"#, options: .regularExpression) != nil {
                return parts.url
            }
            if type == .observed, parts.host == "codex-resets.com", parts.path == "/" { return parts.url }
            return nil
        }
    }

    struct Meta: Decodable, Sendable {
        let apiVersion: String
        let generatedAt: Date
    }

    let data: Payload
    let meta: Meta

    public static func parse(_ data: Data) throws -> PublicResetStatus {
        guard data.count <= 262_144,
              let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = raw["data"] as? [String: Any],
              ["latest_reset", "scheduled_reset", "active_watch"].allSatisfy({ payload.keys.contains($0) }),
              let meta = raw["meta"] as? [String: Any], meta["api_version"] as? String == "v1" else {
            throw PublicResetError.invalidResponse
        }
        if let scheduled = payload["scheduled_reset"] as? [String: Any], !scheduled.keys.contains("scheduled_for") {
            throw PublicResetError.invalidResponse
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: value) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid announcement timestamp")
            }
            return date
        }
        let result = try decoder.decode(PublicResetStatus.self, from: data)
        if let chance = result.data.activeWatch?.resetChancePercent, !(0...100).contains(chance) {
            throw PublicResetError.invalidResponse
        }
        return result
    }

    public func presentation(now: Date = Date(), timeZone: TimeZone = .autoupdatingCurrent) -> PublicResetPresentation {
        let title: String
        var sourceURL: URL?
        var detail = "本机时区：\(timeZone.identifier)\nCodex Resets · 第三方公告追踪"
        if let scheduled = data.scheduledReset {
            let subject = scheduled.source.type == .xPost && scheduled.source.author == "thsottiaux" ? "Tibo" : "公共"
            let action = scheduled.resetType == .banked ? "发券" : "重置"
            if let date = scheduled.scheduledFor {
                title = "\(subject) \(action)：\(date <= now ? "待确认" : "预计") \(Self.dateText(date, timeZone: timeZone))"
            } else {
                title = "\(subject) \(action)：已预告，时间待定"
            }
            sourceURL = scheduled.source.safeURL
            detail += "\n公告发布：\(Self.dateText(scheduled.announcedAt, timeZone: timeZone))\n\(Self.clean(scheduled.text))"
        } else if let watch = data.activeWatch, watch.expiresAt > now {
            title = "重置预测（非官方）：" + (watch.resetChancePercent.map { "\($0)%" } ?? "有动向")
            sourceURL = watch.source.safeURL
            // A free-text forecast window has no machine-readable timezone. Do not turn
            // its expiry into an ETA or silently reinterpret the source's wording.
            detail += "\n预测原文（时间按原文）：\(Self.clean(watch.forecastWindow))"
            detail += "\n预测有效至：\(Self.dateText(watch.expiresAt, timeZone: timeZone))\n\(Self.clean(watch.text))"
        } else {
            title = "Tibo 重置：暂无预告"
        }
        let latest: String
        if let reset = data.latestReset {
            let label = reset.source.type == .observed ? "最近观测" : (reset.resetType == .banked ? "最近发券公告" : "最近重置公告")
            latest = "\(label)：\(Self.dateText(reset.announcedAt, timeZone: timeZone))"
            if data.scheduledReset == nil, data.activeWatch.map({ $0.expiresAt <= now }) ?? true {
                sourceURL = reset.source.safeURL
            }
            detail += "\n\(latest)\n\(Self.clean(reset.text))"
        } else {
            latest = "最近公告：暂无记录"
        }
        detail += "\n数据生成：\(Self.dateText(meta.generatedAt, timeZone: timeZone))"
        return PublicResetPresentation(title: title, latest: latest,
            detail: detail, sourceURL: sourceURL)
    }

    static func clean(_ text: String) -> String {
        String(text.filter { !$0.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) } }.prefix(500))
    }

    static func dateText(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: date)
    }
}

public enum PublicResetError: Error {
    case invalidResponse
    case unavailable
    case retryLater
}
