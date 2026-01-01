import Foundation
import WhisperKit
import os

struct TranscriptionOutput {
    let text: String
    let words: [WordTiming]
}

enum WhisperKitTranscriberNote: Error {
    case engineNotReady
}

actor WhisperKitTranscriber {
    static let shared = WhisperKitTranscriber()

    private let logger = Logger(subsystem: "SpeakerApp", category: "WhisperKit")
    private var whisperKit: WhisperKit?
    private var loadedModel: String?

    private let defaultModel: String = "base"

    private func emit(_ s: String, onStatus: ((String) -> Void)?) {
        onStatus?(s)
        logger.info("\(s, privacy: .public)")
    }

    func prepare(model: String? = nil, onStatus: ((String) -> Void)? = nil) async throws {
        let modelToUse = model ?? defaultModel

        if let whisperKit, loadedModel == modelToUse {
            emit("Model already loaded (\(modelToUse))", onStatus: onStatus)
            return
        }

        emit("Initializing WhisperKit (\(modelToUse))…", onStatus: onStatus)

        let config = WhisperKitConfig(model: modelToUse)
        let engine = try await WhisperKit(config)

        self.whisperKit = engine
        self.loadedModel = modelToUse

        emit("WhisperKit ready (\(modelToUse))", onStatus: onStatus)
    }

    /// ✅ Added `onStatus:` so the UI can show progress messages.
    func transcribeFile(
        audioURL: URL,
        languageCode: String? = nil,
        model: String? = nil,
        onStatus: ((String) -> Void)? = nil
    ) async throws -> TranscriptionOutput {

        try await prepare(model: model, onStatus: onStatus)

        guard let engine = whisperKit else {
            throw WhisperKitTranscriberNote.engineNotReady
        }

        emit("Building decode options…", onStatus: onStatus)

        var options = DecodingOptions()
        options.wordTimestamps = true
        options.chunkingStrategy = .vad
        options.language = languageCode

        emit("Starting transcription…", onStatus: onStatus)

        let segments = try await engine.transcribe(
            audioPath: audioURL.path,
            decodeOptions: options
        )

        emit("Merging segments…", onStatus: onStatus)

        let merged = TranscriptionUtilities.mergeTranscriptionResults(segments)
        let cleanedText = merged.text.trimmingCharacters(in: .whitespacesAndNewlines)

        emit("Mapping word timestamps…", onStatus: onStatus)

        let mappedWords: [WordTiming] = merged.allWords.map { w in
            WordTiming(
                word: w.word,
                start: Double(w.start),
                end: Double(w.end)
            )
        }

        emit("Done (segments: \(segments.count), words: \(mappedWords.count))", onStatus: onStatus)

        return TranscriptionOutput(text: cleanedText, words: mappedWords)
    }
}
