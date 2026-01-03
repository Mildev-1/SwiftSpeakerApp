import Foundation

enum LanguageFlag {
    /// Best-effort mapping (language -> representative country flag).
    static func emoji(for languageCode: String?) -> String? {
        guard var code = languageCode?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !code.isEmpty else { return nil }

        // Normalize common variants
        code = code.replacingOccurrences(of: "_", with: "-")

        // Handle cases like "pt-BR"
        if code.hasPrefix("pt-br") { return "🇧🇷" }

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
}
