import Foundation

/// Stores manual pause marks that overlay the automatic sentence plan.
struct CutPlanRecord: Codable, Hashable {
    /// Edited sentence text with pause emojis inserted (keyed by SentenceChunk.id)
    var sentenceEdits: [String: String]

    /// Manual cut times PER sentence (absolute timeline in seconds)
    var manualCutsBySentence: [String: [Double]]

    /// ✅ Fine tuning offsets per subchunk (key: sentenceID|startMs_endMs)
    var fineTunesBySubchunk: [String: SegmentFineTune]

    var updatedAt: Date

    // Backward-compat (old field)
    private var legacyManualCutTimes: [Double]?

    init(
        sentenceEdits: [String: String] = [:],
        manualCutsBySentence: [String: [Double]] = [:],
        fineTunesBySubchunk: [String: SegmentFineTune] = [:],
        updatedAt: Date = Date()
    ) {
        self.sentenceEdits = sentenceEdits
        self.manualCutsBySentence = manualCutsBySentence
        self.fineTunesBySubchunk = fineTunesBySubchunk
        self.updatedAt = updatedAt
        self.legacyManualCutTimes = nil
    }

    enum CodingKeys: String, CodingKey {
        case sentenceEdits
        case manualCutsBySentence
        case fineTunesBySubchunk
        case updatedAt
        case manualCutTimes // legacy
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        self.sentenceEdits = (try? c.decode([String: String].self, forKey: .sentenceEdits)) ?? [:]
        self.manualCutsBySentence = (try? c.decode([String: [Double]].self, forKey: .manualCutsBySentence)) ?? [:]
        self.fineTunesBySubchunk = (try? c.decode([String: SegmentFineTune].self, forKey: .fineTunesBySubchunk)) ?? [:]
        self.updatedAt = (try? c.decode(Date.self, forKey: .updatedAt)) ?? Date()

        self.legacyManualCutTimes = try? c.decode([Double].self, forKey: .manualCutTimes)
        if manualCutsBySentence.isEmpty, let legacy = legacyManualCutTimes, !legacy.isEmpty {
            self.manualCutsBySentence["_legacy"] = legacy.sorted()
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(sentenceEdits, forKey: .sentenceEdits)
        try c.encode(manualCutsBySentence, forKey: .manualCutsBySentence)
        try c.encode(fineTunesBySubchunk, forKey: .fineTunesBySubchunk)
        try c.encode(updatedAt, forKey: .updatedAt)
    }
}
