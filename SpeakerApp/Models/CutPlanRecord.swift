import Foundation

/// Per-AudioItem persisted state:
/// - sentence text edits
/// - manual pause cut times (per sentence)
/// - fine-tunes per subchunk
/// - playback settings
/// - preferred transcription language
/// - flagged sentence IDs (Practice)
/// - ✅ hard words (🚀 markers) + fine-tunes
struct CutPlanRecord: Codable, Hashable {
    var sentenceEdits: [String: String]
    var manualCutsBySentence: [String: [Double]]
    var fineTunesBySubchunk: [String: SegmentFineTune]
    var playbackSettings: PlaybackSettings
    var preferredLanguageCode: String
    var updatedAt: Date

    /// Practice: persisted flags (SentenceChunk.id)
    var flaggedSentenceIDs: Set<String>

    /// ✅ NEW: hard words extracted per sentence (SentenceChunk.id)
    var hardWordsBySentence: [String: [HardWordSegment]]

    /// ✅ NEW: fine-tune offsets for hard words (HardWordSegment.id)
    var fineTunesByHardWord: [String: SegmentFineTune]

    // legacy
    private var legacyManualCutTimes: [Double]?

    init(
        sentenceEdits: [String: String] = [:],
        manualCutsBySentence: [String: [Double]] = [:],
        fineTunesBySubchunk: [String: SegmentFineTune] = [:],
        playbackSettings: PlaybackSettings = PlaybackSettings(),
        preferredLanguageCode: String = "auto",
        updatedAt: Date = Date(),
        flaggedSentenceIDs: Set<String> = [],
        hardWordsBySentence: [String: [HardWordSegment]] = [:],
        fineTunesByHardWord: [String: SegmentFineTune] = [:]
    ) {
        self.sentenceEdits = sentenceEdits
        self.manualCutsBySentence = manualCutsBySentence
        self.fineTunesBySubchunk = fineTunesBySubchunk
        self.playbackSettings = playbackSettings
        self.preferredLanguageCode = preferredLanguageCode
        self.updatedAt = updatedAt
        self.flaggedSentenceIDs = flaggedSentenceIDs
        self.hardWordsBySentence = hardWordsBySentence
        self.fineTunesByHardWord = fineTunesByHardWord
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

        case hardWordsBySentence
        case fineTunesByHardWord

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

        self.flaggedSentenceIDs = (try? c.decode(Set<String>.self, forKey: .flaggedSentenceIDs)) ?? []

        // ✅ NEW (backward compatible)
        self.hardWordsBySentence = (try? c.decode([String: [HardWordSegment]].self, forKey: .hardWordsBySentence)) ?? [:]
        self.fineTunesByHardWord = (try? c.decode([String: SegmentFineTune].self, forKey: .fineTunesByHardWord)) ?? [:]

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

        try c.encode(hardWordsBySentence, forKey: .hardWordsBySentence)
        try c.encode(fineTunesByHardWord, forKey: .fineTunesByHardWord)
        // do not write legacy field anymore
    }
}
