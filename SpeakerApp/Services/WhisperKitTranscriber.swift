import Foundation
import WhisperKit
import os

struct TranscriptionOutput {
    let text: String
    let words: [WordTiming]
    /// Language actually enforced/used for this run (detected-once or user-chosen).
    /// nil means we could not determine/force a language and ran without forcing.
    let languageUsed: String?
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

    private func emit(_ s: String, _ status: ((String) -> Void)?) {
        status?(s)
        logger.info("\(s, privacy: .public)")
    }

    func prepare(model: String? = nil, status: ((String) -> Void)? = nil) async throws {
        let modelToUse = model ?? defaultModel

        if let whisperKit, loadedModel == modelToUse {
            emit("Model already loaded (\(modelToUse))", status)
            return
        }

        emit("Initializing WhisperKit (\(modelToUse))…", status)

        let config = WhisperKitConfig(model: modelToUse)
        let engine = try await WhisperKit(config)

        self.whisperKit = engine
        self.loadedModel = modelToUse

        emit("WhisperKit ready (\(modelToUse))", status)
    }

    /// If languageCode == "auto" (or nil/empty), detect ONCE then FORCE that language
    /// for the whole file to prevent mixed-language output during VAD chunking.
    func transcribeFile(
        audioURL: URL,
        languageCode: String? = nil,
        model: String? = nil,
        _ status: ((String) -> Void)? = nil
    ) async throws -> TranscriptionOutput {

        try await prepare(model: model, status: status)

        guard let engine = whisperKit else {
            throw WhisperKitTranscriberNote.engineNotReady
        }

        let requested = (languageCode ?? "auto")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        var effectiveLanguage: String? = nil

        if requested.isEmpty || requested == "auto" {
            emit("Detecting language (single pass)…", status)

            var snippetURL: URL? = nil
            var detectPath = audioURL.path

            do {
                snippetURL = try await AudioSnippetExporter.exportFirstM4A(sourceURL: audioURL, seconds: 25.0)
                if let s = snippetURL { detectPath = s.path }
            } catch {
                snippetURL = nil
                detectPath = audioURL.path
            }

            defer {
                if let u = snippetURL { try? FileManager.default.removeItem(at: u) }
            }

            do {
                let (lang, _) = try await engine.detectLanguage(audioPath: detectPath)
                effectiveLanguage = lang
                emit("Detected language: \(lang) (forced for entire file)", status)
            } catch {
                do {
                    let (lang, _) = try await engine.detectLanguage(audioPath: audioURL.path)
                    effectiveLanguage = lang
                    emit("Detected language (fallback): \(lang) (forced for entire file)", status)
                } catch {
                    effectiveLanguage = nil
                    emit("Language detection failed; transcription will run without forcing.", status)
                }
            }
        } else {
            effectiveLanguage = requested
            emit("Language forced: \(requested)", status)
        }

        emit("Building decode options…", status)

        var options = DecodingOptions()
        options.wordTimestamps = true
        options.chunkingStrategy = .vad
        options.task = .transcribe

        // ✅ THE ENFORCEMENT:
        // once we know the language (chosen or detected), force it for the entire file
        options.language = effectiveLanguage

        emit("Starting transcription…", status)

        let segments = try await engine.transcribe(
            audioPath: audioURL.path,
            decodeOptions: options
        )

        emit("Merging segments…", status)

        let merged = TranscriptionUtilities.mergeTranscriptionResults(segments)
        let cleanedText = merged.text.trimmingCharacters(in: .whitespacesAndNewlines)

        let mappedWords: [WordTiming] = merged.allWords.map { w in
            WordTiming(
                word: w.word,
                start: Double(w.start),
                end: Double(w.end)
            )
        }

        emit("Done (segments: \(segments.count), words: \(mappedWords.count))", status)

        return TranscriptionOutput(
            text: cleanedText,
            words: mappedWords,
            languageUsed: effectiveLanguage
        )
    }
}
