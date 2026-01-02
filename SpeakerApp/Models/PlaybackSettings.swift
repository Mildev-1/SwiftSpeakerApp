import Foundation

/// Persisted per AudioItem (stored in CutPlanRecord).
struct PlaybackSettings: Codable, Hashable {
    var repeatPracticeEnabled: Bool
    var practiceRepeats: Int              // 1...3
    var practiceSilenceMultiplier: Double // 0.5...2.0
    var sentencesPauseOnly: Bool          // only used when repeatPracticeEnabled == true

    init(
        repeatPracticeEnabled: Bool = false,
        practiceRepeats: Int = 2,
        practiceSilenceMultiplier: Double = 1.0,
        sentencesPauseOnly: Bool = false
    ) {
        self.repeatPracticeEnabled = repeatPracticeEnabled
        self.practiceRepeats = practiceRepeats
        self.practiceSilenceMultiplier = practiceSilenceMultiplier
        self.sentencesPauseOnly = sentencesPauseOnly
    }

    func clamped() -> PlaybackSettings {
        var x = self
        x.practiceRepeats = min(max(x.practiceRepeats, 1), 3)
        x.practiceSilenceMultiplier = min(max(x.practiceSilenceMultiplier, 0.5), 2.0)
        return x
    }
}
