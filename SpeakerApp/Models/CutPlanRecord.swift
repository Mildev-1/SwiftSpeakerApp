import Foundation

struct CutPlanRecord: Codable, Hashable {
    var sentenceEdits: [String: String]
    var manualCutsBySentence: [String: [Double]]
    var fineTunesBySubchunk: [String: SegmentFineTune]

    /// ✅ NEW: persisted per item
    var playbackSettings: PlaybackSettings

    var updatedAt: Date

    // legacy
    private var legacyManualCutTimes: [Double]?

    init(
        sentenceEdits: [String: String] = [:],
        manualCutsBySentence: [String: [Double]] = [:],
        fineTunesBySubchunk: [String: SegmentFineTune] = [:],
        playbackSettings: PlaybackSettings = PlaybackSettings(),
        updatedAt: Date = Date()
    ) {
        self.sentenceEdits = sentenceEdits
        self.manualCutsBySentence = manualCutsBySentence
        self.fineTunesBySubchunk = fineTunesBySubchunk
        self.playbackSettings = playbackSettings
        self.updatedAt = updatedAt
        self.legacyManualCutTimes = nil
    }

    enum CodingKeys: String, CodingKey {
        case sentenceEdits
        case manualCutsBySentence
        case fineTunesBySubchunk
        case playbackSettings
        case updatedAt
        case manualCutTimes // legacy
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        self.sentenceEdits = (try? c.decode([String: String].self, forKey: .sentenceEdits)) ?? [:]
        self.manualCutsBySentence = (try? c.decode([String: [Double]].self, forKey: .manualCutsBySentence)) ?? [:]
        self.fineTunesBySubchunk = (try? c.decode([String: SegmentFineTune].self, forKey: .fineTunesBySubchunk)) ?? [:]
        self.playbackSettings = (try? c.decode(PlaybackSettings.self, forKey: .playbackSettings)) ?? PlaybackSettings()
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
        try c.encode(playbackSettings, forKey: .playbackSettings)
        try c.encode(updatedAt, forKey: .updatedAt)
        // do not write legacy field anymore
    }
}
