import Foundation
import WhisperKit

// Your app model (keep using your existing WordTiming type)
struct TranscriptionOutput {
    let text: String
    let words: [WordTiming]
}

enum WhisperKitTranscriberNote: Error {
    case engineNotReady
}

/// Runs WhisperKit on-device and returns merged transcript + word timestamps.
/// Implemented as an actor so WhisperKit init/transcribe is serialized safely.
actor WhisperKitTranscriber {
    static let shared = WhisperKitTranscriber()

    private var whisperKit: WhisperKit?
    private var loadedModel: String?

    /// Pick a multilingual model so you can do EN/ES/PT.
    /// (You can change this later to "small", etc.)
    private let defaultModel: String = "base"

    func prepare(model: String? = nil) async throws {
        let modelToUse = model ?? defaultModel

        if let whisperKit, loadedModel == modelToUse {
            return
        }

        let config = WhisperKitConfig(model: modelToUse)
        let engine = try await WhisperKit(config)

        self.whisperKit = engine
        self.loadedModel = modelToUse
    }

    /// Transcribe a local audio file path (mp3/m4a/wav/flac supported by WhisperKit),
    /// merge results, and map WhisperKit.WordTiming -> your app WordTiming.
    func transcribeFile(
        audioURL: URL,
        languageCode: String? = nil,
        model: String? = nil
    ) async throws -> TranscriptionOutput {

        try await prepare(model: model)

        guard let engine = whisperKit else {
            throw WhisperKitTranscriberNote.engineNotReady
        }

        // Configure decoding
        var options = DecodingOptions()
        options.wordTimestamps = true
        options.chunkingStrategy = .vad  // better long-form stability :contentReference[oaicite:2]{index=2}

        // Optional language hint (you can pass "en", "es", "pt")
        // If you leave nil, Whisper will try to auto-detect (quality varies by model/audio).
        options.language = languageCode

        // IMPORTANT: parameter label is `decodeOptions:` :contentReference[oaicite:3]{index=3}
        let segments = try await engine.transcribe(
            audioPath: audioURL.path,
            decodeOptions: options
        )

        // Merge all segments into a single result (text + timings)
        let merged = TranscriptionUtilities.mergeTranscriptionResults(segments)

        let cleanedText = merged.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

        // WhisperKit exposes word timings on the merged result
        let mappedWords: [WordTiming] = merged.allWords.map { w in
            WordTiming(
                word: w.word,
                start: Double(w.start),
                end: Double(w.end)
            )
        }

        return TranscriptionOutput(text: cleanedText, words: mappedWords)
    }
}
