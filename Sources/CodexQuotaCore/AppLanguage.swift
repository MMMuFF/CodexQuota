import Foundation

public enum AppLanguage: Equatable, Sendable {
    case chinese, english

    public static var current: AppLanguage {
        resolve(Locale.preferredLanguages)
    }

    public static func resolve(_ preferredLanguages: [String]) -> AppLanguage {
        preferredLanguages.first?.lowercased().hasPrefix("zh") == true ? .chinese : .english
    }
}

/// Paired copy keeps both supported languages visible at the call site, including interpolated values.
public func L(_ chinese: String, _ english: String) -> String {
    AppLanguage.current == .chinese ? chinese : english
}
