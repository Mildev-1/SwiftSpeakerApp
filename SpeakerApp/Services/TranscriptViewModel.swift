import Foundation
import Combine

@MainActor
final class TranscriptViewModel: ObservableObject {
    @Published var isTranscribing: Bool = false
    @Published var transcriptText: String = ""
    @Published var words: [WordTiming] = []
    @Published var sentenceChunks: [SentenceChunk] = []
    @Published var errorMessage: String? = nil
    @Published var statusText: String = ""

    @Published var sentenceEdits: [String: String] = [:]
    @Published var manualCutsBySentence: [String: [Double]] = [:]
    @Published var fineTunesBySubchunk: [String: SegmentFineTune] = [:]

    @Published var playbackSettings: PlaybackSettings = PlaybackSettings()
    @Published var preferredLanguageCode: String = "auto"

    /// ✅ Practice: persisted flags (SentenceChunk.id)
    @Published var flaggedSentenceIDs: Set<String> = []

    @Published private(set) var hasCachedTranscript: Bool = false

    private let transcriptStore = TranscriptStore.shared
    private let cutPlanStore = CutPlanStore.shared

    private let allowedLangs: Set<String> = ["auto","en","pl","es","de","fr","it","uk","ru","pt"]

    private func normalizeLang(_ s: String) -> String {
        let x = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return allowedLangs.contains(x) ? x : "auto"
    }

    func loadIfAvailable(itemID: UUID) {
        do {
            var recordLang: String? = nil

            if let record = try transcriptStore.load(itemID: itemID) {
                transcriptText = record.text
                words = record.words
                sentenceChunks = SentenceChunkBuilder.build(from: record.words)
                hasCachedTranscript = !record.text.isEmpty
                statusText = "Loaded cached transcript"
                errorMessage = nil
                recordLang = record.languageCode
            } else {
                transcriptText = ""
                words = []
                sentenceChunks = []
                hasCachedTranscript = false
                statusText = ""
                recordLang = nil
            }

            if let plan = try cutPlanStore.load(itemID: itemID) {
                let validIDs = Set(sentenceChunks.map { $0.id })

                sentenceEdits = plan.sentenceEdits.filter { validIDs.contains($0.key) }

                var cuts = plan.manualCutsBySentence
                cuts = cuts.filter { $0.key == "_legacy" || validIDs.contains($0.key) }
                manualCutsBySentence = cuts

                fineTunesBySubchunk = plan.fineTunesBySubchunk.filter { key, _ in
                    let sid = key.split(separator: "|").first.map(String.init) ?? ""
                    return validIDs.contains(sid)
                }

                playbackSettings = plan.playbackSettings.clamped()

                preferredLanguageCode = normalizeLang(plan.preferredLanguageCode)

                // ✅ flags
                flaggedSentenceIDs = plan.flaggedSentenceIDs.intersection(validIDs)
            } else {
                sentenceEdits = [:]
                manualCutsBySentence = [:]
                fineTunesBySubchunk = [:]
                playbackSettings = PlaybackSettings()
                flaggedSentenceIDs = []

                if let rl = recordLang {
                    preferredLanguageCode = normalizeLang(rl)
                } else {
                    preferredLanguageCode = "auto"
                }
            }

        } catch {
            hasCachedTranscript = false
            errorMessage = error.localizedDescription
        }
    }

    func saveCutPlan(itemID: UUID) {
        do {
            let plan = CutPlanRecord(
                sentenceEdits: sentenceEdits,
                manualCutsBySentence: manualCutsBySentence,
                fineTunesBySubchunk: fineTunesBySubchunk,
                playbackSettings: playbackSettings.clamped(),
                preferredLanguageCode: normalizeLang(preferredLanguageCode),
                updatedAt: Date(),
                flaggedSentenceIDs: flaggedSentenceIDs
            )
            try cutPlanStore.save(itemID: itemID, record: plan)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setPlaybackSettings(itemID: UUID, _ newValue: PlaybackSettings) {
        playbackSettings = newValue.clamped()
        saveCutPlan(itemID: itemID)
    }

    func displayText(for chunk: SentenceChunk) -> String {
        sentenceEdits[chunk.id] ?? chunk.text
    }

    func syncManualCutsForSentence(itemID: UUID, chunk: SentenceChunk, finalEditedText: String) {
        sentenceEdits[chunk.id] = finalEditedText

        let newTimes = SentenceCursorTimeMapper.pauseTimesFromEditedText(
            editedText: finalEditedText,
            chunk: chunk,
            allWords: words
        )

        if newTimes.isEmpty {
            manualCutsBySentence.removeValue(forKey: chunk.id)
        } else {
            manualCutsBySentence[chunk.id] = newTimes
        }

        saveCutPlan(itemID: itemID)
    }

    func fineTune(for subchunkID: String) -> SegmentFineTune {
        fineTunesBySubchunk[subchunkID] ?? SegmentFineTune()
    }

    func setFineTune(itemID: UUID, subchunkID: String, startOffset: Double, endOffset: Double) {
        let clamp: (Double) -> Double = { min(0.5, max(-0.5, $0)) }
        fineTunesBySubchunk[subchunkID] = SegmentFineTune(
            startOffset: clamp(startOffset),
            endOffset: clamp(endOffset)
        )
        saveCutPlan(itemID: itemID)
    }

    // MARK: - Practice flags

    func isFlagged(sentenceID: String) -> Bool {
        flaggedSentenceIDs.contains(sentenceID)
    }

    func toggleFlag(itemID: UUID, sentenceID: String) {
        if flaggedSentenceIDs.contains(sentenceID) {
            flaggedSentenceIDs.remove(sentenceID)
        } else {
            flaggedSentenceIDs.insert(sentenceID)
        }
        saveCutPlan(itemID: itemID)
    }

    // MARK: - Transcription

    func transcribeFromMP3(
        itemID: UUID,
        mp3URL: URL,
        languageCode: String? = nil,
        model: String? = "base",
        force: Bool = false
    ) async {
        if !force {
            loadIfAvailable(itemID: itemID)
            if hasCachedTranscript { return }
        }

        isTranscribing = true
        errorMessage = nil
        statusText = "Transcribing…"
        transcriptText = ""
        words = []
        sentenceChunks = []
        hasCachedTranscript = false

        let requested = normalizeLang(languageCode ?? preferredLanguageCode)

        defer { isTranscribing = false }

        do {
            let output = try await WhisperKitTranscriber.shared.transcribeFile(
                audioURL: mp3URL,
                languageCode: requested,
                model: model
            ) { [weak self] s in
                DispatchQueue.main.async {
                    self?.statusText = s
                }
            }

            transcriptText = output.text
            words = output.words
            sentenceChunks = SentenceChunkBuilder.build(from: output.words)

            hasCachedTranscript = !output.text.isEmpty
            statusText = "Saved transcript"

            let langToStore: String? = output.languageUsed ?? (requested == "auto" ? nil : requested)

            // ✅ FIX: TranscriptRecord requires model:
            let record = TranscriptRecord(
                text: output.text,
                words: output.words,
                languageCode: langToStore,
                model: model
            )
            try transcriptStore.save(itemID: itemID, record: record)

            // prune persisted maps by new sentence IDs
            let validIDs = Set(sentenceChunks.map { $0.id })
            sentenceEdits = sentenceEdits.filter { validIDs.contains($0.key) }
            manualCutsBySentence = manualCutsBySentence.filter { $0.key == "_legacy" || validIDs.contains($0.key) }
            fineTunesBySubchunk = fineTunesBySubchunk.filter { key, _ in
                let sid = key.split(separator: "|").first.map(String.init) ?? ""
                return validIDs.contains(sid)
            }

            // keep only flags that still match sentence IDs
            flaggedSentenceIDs = flaggedSentenceIDs.intersection(validIDs)

            saveCutPlan(itemID: itemID)

        } catch {
            errorMessage = error.localizedDescription
            statusText = "Failed"
        }
    }
}
