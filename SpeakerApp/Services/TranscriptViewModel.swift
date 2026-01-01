import Foundation
import Combine

@MainActor
final class TranscriptViewModel: ObservableObject {
    @Published var isTranscribing: Bool = false
    @Published var transcriptText: String = ""
    @Published var words: [WordTiming] = []
    @Published var sentenceChunks: [SentenceChunk] = []   // ✅ NEW
    @Published var errorMessage: String? = nil
    @Published var statusText: String = ""

    @Published private(set) var hasCachedTranscript: Bool = false

    private let store = TranscriptStore.shared

    // UI-only formatted text (still useful, but interactive UI should use `sentenceChunks`)
    var formattedTranscriptForDisplay: String {
        Self.formatSentencesForDisplay(transcriptText)
    }

    func loadIfAvailable(itemID: UUID) {
        do {
            if let record = try store.load(itemID: itemID) {
                transcriptText = record.text
                words = record.words
                sentenceChunks = SentenceChunkBuilder.build(from: record.words) // ✅ NEW
                hasCachedTranscript = !record.text.isEmpty
                statusText = "Loaded cached transcript"
                errorMessage = nil
            } else {
                transcriptText = ""
                words = []
                sentenceChunks = [] // ✅ NEW
                hasCachedTranscript = false
                statusText = ""
            }
        } catch {
            hasCachedTranscript = false
            errorMessage = error.localizedDescription
        }
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
        sentenceChunks = [] // ✅ NEW
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
            sentenceChunks = SentenceChunkBuilder.build(from: output.words) // ✅ NEW

            hasCachedTranscript = !output.text.isEmpty
            statusText = "Saved transcript"

            let record = TranscriptRecord(
                text: output.text,
                words: output.words,
                languageCode: languageCode,
                model: model
            )
            try store.save(itemID: itemID, record: record)

        } catch {
            errorMessage = error.localizedDescription
            statusText = "Failed"
        }
    }

    // MARK: - Formatting helper (UI only)

    private static func formatSentencesForDisplay(_ text: String) -> String {
        guard !text.isEmpty else { return "" }

        let pattern = #"((?<!\d)\.|[?!…])(\s+)(?=\S)"#

        if let re = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            var replaced = re.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "$1\n\n")

            replaced = replaced.replacingOccurrences(of: "\r\n", with: "\n")
            replaced = replaced.replacingOccurrences(of: "\n\n\n+", with: "\n\n", options: .regularExpression)
            replaced = replaced.replacingOccurrences(of: " \n", with: "\n")
            return replaced.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return text
            .replacingOccurrences(of: ". ", with: ".\n\n")
            .replacingOccurrences(of: "? ", with: "?\n\n")
            .replacingOccurrences(of: "! ", with: "!\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
