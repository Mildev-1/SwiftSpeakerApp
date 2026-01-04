import Foundation

enum LanguageFlag {
    struct Option: Identifiable, Hashable {
        let id: String       // languageCode to store (or "auto")
        let label: String    // UI label
        let emoji: String
    }

    /// Options shown when user taps the flag.
    static let pickerOptions: [Option] = [
        .init(id: "auto", label: "Auto (detected)", emoji: "✨"),
        .init(id: "en-US", label: "English (US)", emoji: "🇺🇸"),
        .init(id: "en-CA", label: "English (Canada)", emoji: "🇨🇦"),
        .init(id: "en-GB", label: "English (UK)", emoji: "🇬🇧"),
        .init(id: "es", label: "Spanish", emoji: "🇪🇸"),
        .init(id: "pl", label: "Polish", emoji: "🇵🇱"),
        .init(id: "de", label: "German", emoji: "🇩🇪"),
        .init(id: "fr", label: "French", emoji: "🇫🇷"),
        .init(id: "it", label: "Italian", emoji: "🇮🇹"),
        .init(id: "uk", label: "Ukrainian", emoji: "🇺🇦"),
        .init(id: "ru", label: "Russian", emoji: "🇷🇺"),
        .init(id: "pt", label: "Portuguese", emoji: "🇵🇹"),
        .init(id: "pt-BR", label: "Portuguese (Brazil)", emoji: "🇧🇷"),
        .init(id: "ja", label: "Japanese", emoji: "🇯🇵"),
        .init(id: "ko", label: "Korean", emoji: "🇰🇷"),
        .init(id: "zh", label: "Chinese (Simplified)", emoji: "🇨🇳"),
        .init(id: "zh-TW", label: "Chinese (Traditional)", emoji: "🇹🇼")
    ]

    /// Best-effort mapping (language -> representative flag).
    static func emoji(for languageCode: String?) -> String? {
        guard var code = languageCode?.trimmingCharacters(in: .whitespacesAndNewlines),
              !code.isEmpty else { return nil }

        code = code.replacingOccurrences(of: "_", with: "-").lowercased()

        // explicit variants
        if code.hasPrefix("en-ca") { return "🇨🇦" }
        if code.hasPrefix("en-gb") { return "🇬🇧" }
        if code.hasPrefix("en-us") { return "🇺🇸" }
        if code.hasPrefix("pt-br") { return "🇧🇷" }

        // generic language codes
        switch code {
        case "en": return "🇺🇸"
        case "es": return "🇪🇸"
        case "pl": return "🇵🇱"
        case "de": return "🇩🇪"
        case "fr": return "🇫🇷"
        case "it": return "🇮🇹"
        case "uk": return "🇺🇦"
        case "ru": return "🇷🇺"
        case "pt": return "🇵🇹"
        case "nl": return "🇳🇱"
        case "sv": return "🇸🇪"
        case "no": return "🇳🇴"
        case "da": return "🇩🇰"
        case "fi": return "🇫🇮"
        case "el": return "🇬🇷"
        case "tr": return "🇹🇷"
        case "ja": return "🇯🇵"
        case "ko": return "🇰🇷"
        case "zh", "zh-cn", "zh-hans": return "🇨🇳"
        case "zh-tw", "zh-hant": return "🇹🇼"
        case "ar": return "🇸🇦"
        case "he": return "🇮🇱"
        case "hi": return "🇮🇳"
        default:
            return nil
        }
    }

    /// Normalizes what we store.
    /// - If user chooses "auto", we store nil (so transcript detection can win)
    static func storedCode(from pickerID: String) -> String? {
        let trimmed = pickerID.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed.lowercased() == "auto" { return nil }
        return trimmed
    }
}
