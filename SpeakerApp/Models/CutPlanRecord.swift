import Foundation

/// Per-AudioItem persisted state:
/// - sentence text edits
/// - manual pause cut times (per sentence)
/// - fine-tunes per subchunk
/// - playback settings
/// - preferred transcription language
/// - ✅ flagged sentence IDs (Practice)
struct CutPlanRecord: Codable, Hashable {
    var sentenceEdits: [String: String]
    var manualCutsBySentence: [String: [Double]]
    var fineTunesBySubchunk: [String: SegmentFineTune]
    var playbackSettings: PlaybackSettings
    var preferredLanguageCode: String
    var updatedAt: Date

    /// ✅ NEW: flagged sentence IDs (SentenceChunk.id)
    var flaggedSentenceIDs: Set<String>

    // legacy
    private var legacyManualCutTimes: [Double]?

    init(
        sentenceEdits: [String: String] = [:],
        manualCutsBySentence: [String: [Double]] = [:],
        fineTunesBySubchunk: [String: SegmentFineTune] = [:],
        playbackSettings: PlaybackSettings = PlaybackSettings(),
        preferredLanguageCode: String = "auto",
        updatedAt: Date = Date(),
        flaggedSentenceIDs: Set<String> = []
    ) {
        self.sentenceEdits = sentenceEdits
        self.manualCutsBySentence = manualCutsBySentence
        self.fineTunesBySubchunk = fineTunesBySubchunk
        self.playbackSettings = playbackSettings
        self.preferredLanguageCode = preferredLanguageCode
        self.updatedAt = updatedAt
        self.flaggedSentenceIDs = flaggedSentenceIDs
        self.legacyManualCutTimes = nil
    }

    enum CodingKeys: String, CodingKey {
        case sentenceEdits
        case manualCutsBySentence
        case fineTunesBySubchunk
        case playbackSettings
        case preferredLanguageCode
        case updatedAt
        case flaggedSentenceIDs
        case manualCutTimes // legacy
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        self.sentenceEdits = (try? c.decode([String: String].self, forKey: .sentenceEdits)) ?? [:]
        self.manualCutsBySentence = (try? c.decode([String: [Double]].self, forKey: .manualCutsBySentence)) ?? [:]
        self.fineTunesBySubchunk = (try? c.decode([String: SegmentFineTune].self, forKey: .fineTunesBySubchunk)) ?? [:]
        self.playbackSettings = (try? c.decode(PlaybackSettings.self, forKey: .playbackSettings)) ?? PlaybackSettings()
        self.preferredLanguageCode = (try? c.decode(String.self, forKey: .preferredLanguageCode)) ?? "auto"
        self.updatedAt = (try? c.decode(Date.self, forKey: .updatedAt)) ?? Date()

        // ✅ backward compatible: older JSON won’t have this
        self.flaggedSentenceIDs = (try? c.decode(Set<String>.self, forKey: .flaggedSentenceIDs)) ?? []

        // legacy manual cuts
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
        try c.encode(preferredLanguageCode, forKey: .preferredLanguageCode)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(flaggedSentenceIDs, forKey: .flaggedSentenceIDs)
        // do not write legacy field anymore
    }
}
