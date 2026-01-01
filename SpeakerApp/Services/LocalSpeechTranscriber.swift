import Foundation
import Speech

struct LocalTranscriptResult {
    let text: String
    let words: [WordTiming]
}

enum LocalSpeechTranscriber {
    enum TranscribeError: LocalizedError {
        case notAuthorized
        case onDeviceNotSupported
        case noRecognizer
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "Speech recognition is not authorized. Enable it in Settings."
            case .onDeviceNotSupported:
                return "On-device speech recognition is not supported for this language/device."
            case .noRecognizer:
                return "Speech recognizer is unavailable."
            case .failed(let msg):
                return "Transcription failed: \(msg)"
            }
        }
    }

    static func requestAuthorization() async throws {
        let status = await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in cont.resume(returning: status) }
        }
        guard status == .authorized else { throw TranscribeError.notAuthorized }
    }

    static func transcribeOffline(audioURL: URL, locale: Locale = .current) async throws -> LocalTranscriptResult {
        try await requestAuthorization()

        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw TranscribeError.noRecognizer
        }
        guard recognizer.isAvailable else {
            throw TranscribeError.noRecognizer
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw TranscribeError.onDeviceNotSupported
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false

        if #available(iOS 16.0, *) {
            request.addsPunctuation = true
        }

        return try await withCheckedThrowingContinuation { continuation in
            var didResume = false
            var task: SFSpeechRecognitionTask? = nil   // ✅ declare before closure

            task = recognizer.recognitionTask(with: request) { result, error in
                if let error = error, !didResume {
                    didResume = true
                    continuation.resume(throwing: TranscribeError.failed(error.localizedDescription))
                    task?.cancel()
                    task = nil
                    return
                }

                guard let result = result, result.isFinal, !didResume else { return }
                didResume = true

                let transcription = result.bestTranscription
                let text = transcription.formattedString

                let words: [WordTiming] = transcription.segments.compactMap { seg in
                    let raw = seg.substring.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !raw.isEmpty else { return nil }
                    let start = seg.timestamp
                    let end = seg.timestamp + seg.duration
                    return WordTiming(word: raw, start: start, end: end)
                }

                continuation.resume(returning: LocalTranscriptResult(text: text, words: words))
                task?.cancel()
                task = nil
            }
        }
    }
}
