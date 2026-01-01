import Foundation
import Combine

@MainActor
final class TranscriptViewModel: ObservableObject {
    @Published var isTranscribing: Bool = false
    @Published var transcriptText: String = ""
    @Published var words: [WordTiming] = []
    @Published var errorMessage: String? = nil

    // debug/progress
    @Published var progress: Double = 0.0
    @Published var chunksTotal: Int = 0
    @Published var chunkIndex: Int = 0

    /// Transcribe a (stored) MP3 by exporting to multiple short M4A chunks and transcribing each chunk offline.
    /// This works around Speech framework's practical ~1 minute per-request behavior.
    func transcribeFromMP3(mp3URL: URL, locale: Locale = .current) async {
        isTranscribing = true
        errorMessage = nil
        progress = 0
        transcriptText = ""
        words = []
        chunksTotal = 0
        chunkIndex = 0

        var tempChunkURLs: [URL] = []
        var chunkErrors: [String] = []

        defer {
            // Clean up temp files
            for url in tempChunkURLs { try? FileManager.default.removeItem(at: url) }
            isTranscribing = false
        }

        do {
            let chunks = try await AudioChunkExporter.exportM4AChunks(sourceURL: mp3URL, chunkSeconds: 55.0)
            chunksTotal = chunks.count

            guard !chunks.isEmpty else {
                errorMessage = "No chunks were produced."
                return
            }

            for (i, chunk) in chunks.enumerated() {
                chunkIndex = i + 1
                progress = Double(i) / Double(chunks.count)

                tempChunkURLs.append(chunk.url)

                do {
                    let result = try await LocalSpeechTranscriber.transcribeOffline(
                        audioURL: chunk.url,
                        locale: locale
                    )

                    // Merge text
                    if !result.text.isEmpty {
                        if !transcriptText.isEmpty { transcriptText += " " }
                        transcriptText += result.text
                    }

                    // Merge word timings (offset by chunk start)
                    let adjusted: [WordTiming] = result.words.map { w in
                        WordTiming(
                            word: w.word,
                            start: w.start + chunk.startOffset,
                            end: w.end + chunk.startOffset
                        )
                    }
                    words.append(contentsOf: adjusted)

                } catch {
                    // Keep going, collect errors
                    chunkErrors.append("Chunk \(i + 1)/\(chunks.count): \(error.localizedDescription)")
                }

                progress = Double(i + 1) / Double(chunks.count)
            }

            // If some chunks failed, show a summary but keep whatever we got
            if !chunkErrors.isEmpty {
                // show first error + count (avoid huge UI spam)
                let first = chunkErrors.first ?? "Unknown error"
                errorMessage = "\(chunkErrors.count) chunk(s) failed. First error: \(first)"
            } else {
                errorMessage = nil
            }

        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
