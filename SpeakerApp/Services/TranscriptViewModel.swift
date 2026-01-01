import Foundation
import Combine
import AVFoundation

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

    // extra debug so you can confirm the chunk durations are correct
    @Published var chunkDurations: [Double] = []

    /// ✅ Correct approach:
    /// MP3 -> (full) M4A -> chunk M4A -> Speech per chunk -> merge text + word timings
    func transcribeFromMP3(mp3URL: URL, locale: Locale = .current) async {
        isTranscribing = true
        errorMessage = nil
        progress = 0
        transcriptText = ""
        words = []
        chunksTotal = 0
        chunkIndex = 0
        chunkDurations = []

        var tempURLsToDelete: [URL] = []
        var chunkErrors: [String] = []

        defer {
            for url in tempURLsToDelete { try? FileManager.default.removeItem(at: url) }
            isTranscribing = false
        }

        do {
            // 1) Transcode full MP3 to a single M4A (stable timeline)
            let fullM4AURL = try await AudioTranscoder.toM4A(sourceURL: mp3URL)
            tempURLsToDelete.append(fullM4AURL)

            // 2) Chunk the M4A (not the MP3)
            let chunks = try await AudioChunkExporter.exportM4AChunks(sourceURL: fullM4AURL, chunkSeconds: 55.0)
            chunksTotal = chunks.count

            guard !chunks.isEmpty else {
                errorMessage = "No chunks were produced."
                return
            }

            for (i, chunk) in chunks.enumerated() {
                chunkIndex = i + 1
                progress = Double(i) / Double(chunks.count)

                tempURLsToDelete.append(chunk.url)

                // Debug actual duration of exported chunk
                let dur = await loadDurationSeconds(url: chunk.url)
                chunkDurations.append(dur)

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
                    chunkErrors.append("Chunk \(i + 1)/\(chunks.count) failed: \(error.localizedDescription)")
                }

                progress = Double(i + 1) / Double(chunks.count)
            }

            if !chunkErrors.isEmpty {
                let first = chunkErrors.first ?? "Unknown error"
                errorMessage = "\(chunkErrors.count) chunk(s) failed. First: \(first)"
            } else {
                errorMessage = nil
            }

        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadDurationSeconds(url: URL) async -> Double {
        let asset = AVURLAsset(url: url)
        do {
            if #available(iOS 15.0, *) {
                let d = try await asset.load(.duration)
                return d.seconds.isFinite ? d.seconds : 0
            } else {
                let d = asset.duration
                return d.seconds.isFinite ? d.seconds : 0
            }
        } catch {
            return 0
        }
    }
}
