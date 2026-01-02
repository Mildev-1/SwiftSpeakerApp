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

    /// ✅ NEW: per-item playback settings (persisted in CutPlanRecord)
    @Published var playbackSettings: PlaybackSettings = PlaybackSettings()

    @Published private(set) var hasCachedTranscript: Bool = false

    private let transcriptStore = TranscriptStore.shared
    private let cutPlanStore = CutPlanStore.shared

    func loadIfAvailable(itemID: UUID) {
        do {
            if let record = try transcriptStore.load(itemID: itemID) {
                transcriptText = record.text
                words = record.words
                sentenceChunks = SentenceChunkBuilder.build(from: record.words)
                hasCachedTranscript = !record.text.isEmpty
                statusText = "Loaded cached transcript"
                errorMessage = nil
            } else {
                transcriptText = ""
                words = []
                sentenceChunks = []
                hasCachedTranscript = false
                statusText = ""
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
            } else {
                sentenceEdits = [:]
                manualCutsBySentence = [:]
                fineTunesBySubchunk = [:]
                playbackSettings = PlaybackSettings()
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
                updatedAt: Date()
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

        defer { isTranscribing = false }

        do {
            let output = try await WhisperKitTranscriber.shared.transcribeFile(
                audioURL: mp3URL,
                languageCode: languageCode,
                model: model,
                onStatus: { [weak self] s in
                    Task { @MainActor in self?.statusText = s }
                }
            )

            transcriptText = output.text
            words = output.words
            sentenceChunks = SentenceChunkBuilder.build(from: output.words)

            hasCachedTranscript = !output.text.isEmpty
            statusText = "Saved transcript"

            let record = TranscriptRecord(
                text: output.text,
                words: output.words,
                languageCode: languageCode,
                model: model
            )
            try transcriptStore.save(itemID: itemID, record: record)

            let validIDs = Set(sentenceChunks.map { $0.id })
            sentenceEdits = sentenceEdits.filter { validIDs.contains($0.key) }
            manualCutsBySentence = manualCutsBySentence.filter { $0.key == "_legacy" || validIDs.contains($0.key) }
            fineTunesBySubchunk = fineTunesBySubchunk.filter { key, _ in
                let sid = key.split(separator: "|").first.map(String.init) ?? ""
                return validIDs.contains(sid)
            }

            saveCutPlan(itemID: itemID)

        } catch {
            errorMessage = error.localizedDescription
            statusText = "Failed"
        }
    }
}
