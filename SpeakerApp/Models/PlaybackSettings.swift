import Foundation

struct PlaybackSettings: Codable, Hashable {
    var repeatPracticeEnabled: Bool
    var practiceRepeats: Int              // 1...3
    var practiceSilenceMultiplier: Double // 0.2...3.0 (UI range)
    var sentencesPauseOnly: Bool          // only used when repeatPracticeEnabled == true

    /// Font scale for Full Screen Playback (1.0...2.2)
    var playbackFontScale: Double

    /// When ON, Partial Play will play only flagged sentences.
    var flaggedOnly: Bool

    // ✅ NEW: Words shadowing settings
    var wordShadowingEnabled: Bool
    var wordPracticeRepeats: Int              // 1...5
    var wordPracticeSilenceMultiplier: Double // 0.2...6.0

    init(
        repeatPracticeEnabled: Bool = false,
        practiceRepeats: Int = 2,
        practiceSilenceMultiplier: Double = 1.0,
        sentencesPauseOnly: Bool = false,
        playbackFontScale: Double = 1.0,
        flaggedOnly: Bool = false,
        wordShadowingEnabled: Bool = false,
        wordPracticeRepeats: Int = 2,
        wordPracticeSilenceMultiplier: Double = 1.5
    ) {
        self.repeatPracticeEnabled = repeatPracticeEnabled
        self.practiceRepeats = practiceRepeats
        self.practiceSilenceMultiplier = practiceSilenceMultiplier
        self.sentencesPauseOnly = sentencesPauseOnly
        self.playbackFontScale = playbackFontScale
        self.flaggedOnly = flaggedOnly
        self.wordShadowingEnabled = wordShadowingEnabled
        self.wordPracticeRepeats = wordPracticeRepeats
        self.wordPracticeSilenceMultiplier = wordPracticeSilenceMultiplier
    }

    func clamped() -> PlaybackSettings {
        var x = self
        x.practiceRepeats = min(max(x.practiceRepeats, 1), 3)
        x.practiceSilenceMultiplier = min(max(x.practiceSilenceMultiplier, 0.2), 3.0)
        x.playbackFontScale = min(max(x.playbackFontScale, 1.0), 2.2)

        x.wordPracticeRepeats = min(max(x.wordPracticeRepeats, 1), 5)
        x.wordPracticeSilenceMultiplier = min(max(x.wordPracticeSilenceMultiplier, 0.2), 6.0)
        return x
    }

    enum CodingKeys: String, CodingKey {
        case repeatPracticeEnabled
        case practiceRepeats
        case practiceSilenceMultiplier
        case sentencesPauseOnly
        case playbackFontScale
        case flaggedOnly

        // ✅ NEW
        case wordShadowingEnabled
        case wordPracticeRepeats
        case wordPracticeSilenceMultiplier
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        self.repeatPracticeEnabled = (try? c.decode(Bool.self, forKey: .repeatPracticeEnabled)) ?? false
        self.practiceRepeats = (try? c.decode(Int.self, forKey: .practiceRepeats)) ?? 2
        self.practiceSilenceMultiplier = (try? c.decode(Double.self, forKey: .practiceSilenceMultiplier)) ?? 1.0
        self.sentencesPauseOnly = (try? c.decode(Bool.self, forKey: .sentencesPauseOnly)) ?? false
        self.playbackFontScale = (try? c.decode(Double.self, forKey: .playbackFontScale)) ?? 1.0
        self.flaggedOnly = (try? c.decode(Bool.self, forKey: .flaggedOnly)) ?? false

        self.wordShadowingEnabled = (try? c.decode(Bool.self, forKey: .wordShadowingEnabled)) ?? false
        self.wordPracticeRepeats = (try? c.decode(Int.self, forKey: .wordPracticeRepeats)) ?? 2
        self.wordPracticeSilenceMultiplier = (try? c.decode(Double.self, forKey: .wordPracticeSilenceMultiplier)) ?? 1.5

        self = self.clamped()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)

        try c.encode(repeatPracticeEnabled, forKey: .repeatPracticeEnabled)
        try c.encode(practiceRepeats, forKey: .practiceRepeats)
        try c.encode(practiceSilenceMultiplier, forKey: .practiceSilenceMultiplier)
        try c.encode(sentencesPauseOnly, forKey: .sentencesPauseOnly)
        try c.encode(playbackFontScale, forKey: .playbackFontScale)
        try c.encode(flaggedOnly, forKey: .flaggedOnly)

        try c.encode(wordShadowingEnabled, forKey: .wordShadowingEnabled)
        try c.encode(wordPracticeRepeats, forKey: .wordPracticeRepeats)
        try c.encode(wordPracticeSilenceMultiplier, forKey: .wordPracticeSilenceMultiplier)
    }
}
