import Foundation

public struct PublicResetPresentation: Sendable {
    public let title: String
    public let latest: String
    public let confidence: String?
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
        let level: String?
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
        var confidence: String?
        var sourceURL: URL?
        var detail = "本机时区：\(timeZone.identifier)\nCodex Resets · 第三方公告追踪"
        if let scheduled = data.scheduledReset {
            let subject = scheduled.source.type == .xPost && scheduled.source.author == "thsottiaux" ? "Tibo" : "公共"
            let action = scheduled.resetType == .banked ? "发券" : "重置"
            if let date = scheduled.scheduledFor {
                title = "\(subject) \(action)：\(date <= now ? "待确认" : "预计") \(Self.dateText(date, timeZone: timeZone))"
                confidence = date <= now ? "预告时间已过 · 待确认" : "已预告 · 待执行"
            } else {
                title = "\(subject) \(action)：已预告，时间待定"
                confidence = "已预告 · 待执行"
            }
            sourceURL = scheduled.source.safeURL
            detail += "\n公告发布：\(Self.dateText(scheduled.announcedAt, timeZone: timeZone))\n\(Self.clean(scheduled.text))"
            detail += "\n明确预告不等于已执行；预告时间已过也不自动确认完成。"
        } else if let watch = data.activeWatch, watch.expiresAt > now {
            title = "重置预测（非官方）：" + (watch.resetChancePercent.map { "\($0)%" } ?? "概率未提供")
            let strength: String
            switch watch.level {
            case "strong": strength = "信号较强"
            case "elevated": strength = "信号增强"
            default: strength = "强度未知"
            }
            confidence = "\(strength) · 非执行保证"
            detail += "\n第三方 AI 预测，不是 Tibo 或 OpenAI 的承诺；接口未提供历史命中率，百分比不代表已验证准确率。"
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
            if confidence == nil {
                confidence = reset.source.type == .observed
                    ? "第三方观测 · 非官方确认" : "已发布公告 · 非个人到账确认"
            }
        } else {
            latest = "最近公告：暂无记录"
        }
        detail += "\n数据生成：\(Self.dateText(meta.generatedAt, timeZone: timeZone))"
        if let confidence { detail += "\n\(confidence)" }
        return PublicResetPresentation(title: title, latest: latest, confidence: confidence,
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
