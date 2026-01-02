import Foundation

/// Persisted per AudioItem (stored in CutPlanRecord).
struct PlaybackSettings: Codable, Hashable {
    var repeatPracticeEnabled: Bool
    var practiceRepeats: Int              // 1...3
    var practiceSilenceMultiplier: Double // 0.5...2.0
    var sentencesPauseOnly: Bool          // only used when repeatPracticeEnabled == true

    /// ✅ NEW: font scale for Full Screen Playback (1.0...3.0)
    var playbackFontScale: Double

    init(
        repeatPracticeEnabled: Bool = false,
        practiceRepeats: Int = 2,
        practiceSilenceMultiplier: Double = 1.0,
        sentencesPauseOnly: Bool = false,
        playbackFontScale: Double = 1.0
    ) {
        self.repeatPracticeEnabled = repeatPracticeEnabled
        self.practiceRepeats = practiceRepeats
        self.practiceSilenceMultiplier = practiceSilenceMultiplier
        self.sentencesPauseOnly = sentencesPauseOnly
        self.playbackFontScale = playbackFontScale
    }

    func clamped() -> PlaybackSettings {
        var x = self
        x.practiceRepeats = min(max(x.practiceRepeats, 1), 3)
        x.practiceSilenceMultiplier = min(max(x.practiceSilenceMultiplier, 0.5), 2.0)
        x.playbackFontScale = min(max(x.playbackFontScale, 1.0), 2.2)
        return x
    }

    // ✅ Backward-compatible decode (older saved JSON won’t have playbackFontScale)
    enum CodingKeys: String, CodingKey {
        case repeatPracticeEnabled
        case practiceRepeats
        case practiceSilenceMultiplier
        case sentencesPauseOnly
        case playbackFontScale
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.repeatPracticeEnabled = (try? c.decode(Bool.self, forKey: .repeatPracticeEnabled)) ?? false
        self.practiceRepeats = (try? c.decode(Int.self, forKey: .practiceRepeats)) ?? 2
        self.practiceSilenceMultiplier = (try? c.decode(Double.self, forKey: .practiceSilenceMultiplier)) ?? 1.0
        self.sentencesPauseOnly = (try? c.decode(Bool.self, forKey: .sentencesPauseOnly)) ?? false
        self.playbackFontScale = (try? c.decode(Double.self, forKey: .playbackFontScale)) ?? 1.0
        self = self.clamped()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(repeatPracticeEnabled, forKey: .repeatPracticeEnabled)
        try c.encode(practiceRepeats, forKey: .practiceRepeats)
        try c.encode(practiceSilenceMultiplier, forKey: .practiceSilenceMultiplier)
        try c.encode(sentencesPauseOnly, forKey: .sentencesPauseOnly)
        try c.encode(playbackFontScale, forKey: .playbackFontScale)
    }
}
