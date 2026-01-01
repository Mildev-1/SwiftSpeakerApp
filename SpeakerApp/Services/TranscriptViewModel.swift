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
    @Published var sentenceEdits: [String: String] = [:]     // chunk.id -> edited text (with ⏸️)
    @Published var manualCutTimes: [Double] = []             // absolute seconds in file

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

            // load cut plan overlay (if any)
            if let plan = try cutPlanStore.load(itemID: itemID) {
                // Keep only edits for chunks that still exist
                let validIDs = Set(sentenceChunks.map { $0.id })
                sentenceEdits = plan.sentenceEdits.filter { validIDs.contains($0.key) }
                manualCutTimes = plan.manualCutTimes.sorted()
            } else {
                sentenceEdits = [:]
                manualCutTimes = []
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
                manualCutTimes: manualCutTimes.sorted(),
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

    /// Add manual cut time (dedupe within 30ms).
    func addManualCutTime(itemID: UUID, time: Double) {
        let t = max(0, time)
        let epsilon = 0.03
        if manualCutTimes.contains(where: { abs($0 - t) < epsilon }) { return }
        manualCutTimes.append(t)
        manualCutTimes.sort()
        saveCutPlan(itemID: itemID)
    }

    /// Update edited sentence text and persist.
    func updateSentenceEdit(itemID: UUID, chunkID: String, newText: String) {
        sentenceEdits[chunkID] = newText
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

            // Keep existing manual plan, but drop edits for chunks that don't exist anymore
            let validIDs = Set(sentenceChunks.map { $0.id })
            sentenceEdits = sentenceEdits.filter { validIDs.contains($0.key) }
            manualCutTimes.sort()
            saveCutPlan(itemID: itemID)

        } catch {
            errorMessage = error.localizedDescription
            statusText = "Failed"
        }
    }
}
