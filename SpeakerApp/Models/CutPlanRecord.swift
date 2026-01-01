import Foundation

/// Stores manual pause marks that overlay the automatic sentence plan.
struct CutPlanRecord: Codable, Hashable {
    /// Edited sentence text with pause emojis inserted (keyed by SentenceChunk.id)
    var sentenceEdits: [String: String]

    /// Manual cut times in seconds (absolute timeline in the audio file)
    var manualCutTimes: [Double]

    var updatedAt: Date

    init(sentenceEdits: [String: String] = [:], manualCutTimes: [Double] = [], updatedAt: Date = Date()) {
        self.sentenceEdits = sentenceEdits
        self.manualCutTimes = manualCutTimes
        self.updatedAt = updatedAt
    }
}
