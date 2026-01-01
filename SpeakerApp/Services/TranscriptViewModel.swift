import Foundation
import Combine

@MainActor
final class TranscriptViewModel: ObservableObject {
    @Published var isTranscribing: Bool = false
    @Published var transcriptText: String = ""
    @Published var words: [WordTiming] = []
    @Published var errorMessage: String? = nil

    // Optional UI progress (WhisperKit itself can provide more detailed progress,
    // but for now this is simple).
    @Published var progress: Double = 0.0

    /// Main entry: transcribe a stored MP3 URL offline (on device) with WhisperKit.
    /// - Parameters:
    ///   - mp3URL: file URL in your app storage
    ///   - languageCode: "en", "es", "pt" (optional). If nil, auto-detect.
    ///   - model: WhisperKit model name (optional). Default set inside WhisperKitTranscriber.
    func transcribeFromMP3(
        mp3URL: URL,
        languageCode: String? = nil,
        model: String? = nil
    ) async {
        isTranscribing = true
        errorMessage = nil
        progress = 0
        transcriptText = ""
        words = []

        defer {
            isTranscribing = false
            progress = 1.0
        }

        do {
            let output = try await WhisperKitTranscriber.shared.transcribeFile(
                audioURL: mp3URL,
                languageCode: languageCode,
                model: model
            )

            transcriptText = output.text
            words = output.words

        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
