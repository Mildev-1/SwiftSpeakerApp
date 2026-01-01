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

    // ✅ Manual overlay plan
    @Published var sentenceEdits: [String: String] = [:]              // chunk.id -> edited text (with ⏸️)
    @Published var manualCutsBySentence: [String: [Double]] = [:]     // chunk.id -> [cut times]

    @Published private(set) var hasCachedTranscript: Bool = false

    private let transcriptStore = TranscriptStore.shared
    private let cutPlanStore = CutPlanStore.shared

    /// Flattened manual cut times (used by playback)
    var manualCutTimesFlattened: [Double] {
        manualCutsBySentence
            .filter { $0.key != "_legacy" }
            .flatMap { $0.value }
            .sorted()
    }

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

                // keep only cuts for valid sentences (but also keep legacy bucket if present)
                var cuts = plan.manualCutsBySentence
                cuts = cuts.filter { $0.key == "_legacy" || validIDs.contains($0.key) }
                manualCutsBySentence = cuts

            } else {
                sentenceEdits = [:]
                manualCutsBySentence = [:]
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
                updatedAt: Date()
            )
            try cutPlanStore.save(itemID: itemID, record: plan)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func displayText(for chunk: SentenceChunk) -> String {
        sentenceEdits[chunk.id] ?? chunk.text
    }

    /// Called when user taps "Pause" button (quick add).
    func addManualCutTime(itemID: UUID, chunkID: String, time: Double) {
        let t = max(0, time)
        let eps = 0.03

        var list = manualCutsBySentence[chunkID] ?? []
        if list.contains(where: { abs($0 - t) < eps }) { return }

        list.append(t)
        list.sort()
        manualCutsBySentence[chunkID] = list
        saveCutPlan(itemID: itemID)
    }

    /// Persist edited text and also sync cuts from ⏸️ markers.
    /// This is the key: deleting emojis removes corresponding cuts.
    func syncManualCutsForSentence(
        itemID: UUID,
        chunk: SentenceChunk,
        finalEditedText: String
    ) {
        // store text
        sentenceEdits[chunk.id] = finalEditedText

        // recompute cuts from the CURRENT text content
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

            // prune invalid edits/cuts (sentence IDs can change if transcription changes)
            let validIDs = Set(sentenceChunks.map { $0.id })
            sentenceEdits = sentenceEdits.filter { validIDs.contains($0.key) }
            manualCutsBySentence = manualCutsBySentence.filter { $0.key == "_legacy" || validIDs.contains($0.key) }

            saveCutPlan(itemID: itemID)

        } catch {
            errorMessage = error.localizedDescription
            statusText = "Failed"
        }
    }
}
