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
        var detail = L("本机时区：\(timeZone.identifier)\nCodex Resets · 第三方公告追踪", "Local time zone: \(timeZone.identifier)\nCodex Resets · Third-party announcement tracker")
        if let scheduled = data.scheduledReset {
            let subject = scheduled.source.type == .xPost && scheduled.source.author == "thsottiaux" ? "Tibo" : L("公共", "Public")
            let action = scheduled.resetType == .banked ? L("发券", "credit grant") : L("重置", "reset")
            if let date = scheduled.scheduledFor {
                title = "\(subject) \(action)\(L("：", ": "))\(date <= now ? L("待确认", "Pending confirmation") : L("预计", "Expected")) \(Self.dateText(date, timeZone: timeZone))"
                confidence = date <= now ? L("预告时间已过 · 待确认", "ETA passed · Not confirmed") : L("已预告 · 待执行", "Announced · Awaiting execution")
            } else {
                title = L("\(subject) \(action)：已预告，时间待定", "\(subject) \(action): announced, time TBD")
                confidence = L("已预告 · 待执行", "Announced · Awaiting execution")
            }
            sourceURL = scheduled.source.safeURL
            detail += L("\n公告发布：\(Self.dateText(scheduled.announcedAt, timeZone: timeZone))\n\(Self.clean(scheduled.text))", "\nPublished: \(Self.dateText(scheduled.announcedAt, timeZone: timeZone))\n\(Self.clean(scheduled.text))")
            detail += L("\n明确预告不等于已执行；预告时间已过也不自动确认完成。", "\nAn announcement is not proof of execution, even after its ETA.")
        } else if let watch = data.activeWatch, watch.expiresAt > now {
            title = L("重置预测（非官方）：", "Reset forecast (unofficial): ") + (watch.resetChancePercent.map { "\($0)%" } ?? L("概率未提供", "Probability not provided"))
            let strength: String
            switch watch.level {
            case "strong": strength = L("信号较强", "Strong signal")
            case "elevated": strength = L("信号增强", "Elevated signal")
            default: strength = L("强度未知", "Unknown signal strength")
            }
            confidence = L("\(strength) · 非执行保证", "\(strength) · Not guaranteed")
            detail += L("\n第三方 AI 预测，不是 Tibo 或 OpenAI 的承诺；接口未提供历史命中率，百分比不代表已验证准确率。", "\nThird-party AI forecast, not a promise by Tibo or OpenAI. The API provides no historical accuracy; the percentage is not a validated success rate.")
            sourceURL = watch.source.safeURL
            // A free-text forecast window has no machine-readable timezone. Do not turn
            // its expiry into an ETA or silently reinterpret the source's wording.
            detail += L("\n预测原文（时间按原文）：\(Self.clean(watch.forecastWindow))", "\nForecast window (original wording): \(Self.clean(watch.forecastWindow))")
            detail += L("\n预测有效至：\(Self.dateText(watch.expiresAt, timeZone: timeZone))\n\(Self.clean(watch.text))", "\nForecast valid until: \(Self.dateText(watch.expiresAt, timeZone: timeZone))\n\(Self.clean(watch.text))")
        } else {
            title = L("Tibo 重置：暂无预告", "Tibo reset: no upcoming notice")
        }
        let latest: String
        if let reset = data.latestReset {
            let label = reset.source.type == .observed ? L("最近观测", "Latest observation") : (reset.resetType == .banked ? L("最近发券公告", "Latest credit notice") : L("最近重置公告", "Latest reset notice"))
            latest = L("\(label)：\(Self.dateText(reset.announcedAt, timeZone: timeZone))", "\(label): \(Self.dateText(reset.announcedAt, timeZone: timeZone))")
            if data.scheduledReset == nil, data.activeWatch.map({ $0.expiresAt <= now }) ?? true {
                sourceURL = reset.source.safeURL
            }
            detail += "\n\(latest)\n\(Self.clean(reset.text))"
            if confidence == nil {
                confidence = reset.source.type == .observed
                    ? L("第三方观测 · 非官方确认", "Third-party observation · Unconfirmed") : L("已发布公告 · 非个人到账确认", "Notice published · Check your own quota")
            }
        } else {
            latest = L("最近公告：暂无记录", "Latest notice: no records")
        }
        detail += L("\n数据生成：\(Self.dateText(meta.generatedAt, timeZone: timeZone))", "\nData generated: \(Self.dateText(meta.generatedAt, timeZone: timeZone))")
        if let confidence { detail += "\n\(confidence)" }
        return PublicResetPresentation(title: title, latest: latest, confidence: confidence,
            detail: detail, sourceURL: sourceURL)
    }

    static func clean(_ text: String) -> String {
        String(text.filter { !$0.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) } }.prefix(500))
    }

    static func dateText(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: L("zh_Hans_CN", "en_US_POSIX"))
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = L("M月d日 HH:mm", "MMM d HH:mm")
        return formatter.string(from: date)
    }
}

public enum PublicResetError: Error {
    case invalidResponse
    case unavailable
    case retryLater
}
