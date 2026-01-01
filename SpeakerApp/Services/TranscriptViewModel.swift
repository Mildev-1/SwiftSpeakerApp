import Foundation
import Combine

@MainActor
final class TranscriptViewModel: ObservableObject {
    @Published var isTranscribing: Bool = false
    @Published var transcriptText: String = ""
    @Published var words: [WordTiming] = []
    @Published var errorMessage: String? = nil

    // UI feedback
    @Published var statusText: String = ""
    @Published var modelBytesOnDisk: Int64 = 0
    @Published var modelExpectedBytes: Int64? = nil
    @Published var modelProgress: Double? = nil  // 0...1 when expected is known

    private var monitorTask: Task<Void, Never>?

    func transcribeFromMP3(
        mp3URL: URL,
        languageCode: String? = nil, // "en", "es", "pt" or nil
        model: String? = nil
    ) async {
        let chosenModel = model ?? "base"

        isTranscribing = true
        errorMessage = nil
        transcriptText = ""
        words = []

        statusText = "Preparing…"
        modelExpectedBytes = WhisperModelInfo.expectedBytes(for: chosenModel)
        modelProgress = nil
        startModelMonitor()

        defer {
            stopModelMonitor()
            isTranscribing = false
            if errorMessage == nil { statusText = "Done" }
        }

        do {
            statusText = "Loading / downloading model… (keep app open)"
            let output = try await WhisperKitTranscriber.shared.transcribeFile(
                audioURL: mp3URL,
                languageCode: languageCode,
                model: chosenModel,
                onStatus: { [weak self] s in
                    Task { @MainActor in self?.statusText = s }
                }
            )

            statusText = "Updating UI…"
            transcriptText = output.text
            words = output.words

        } catch {
            errorMessage = error.localizedDescription
            statusText = "Failed"
        }
    }

    // MARK: - Model monitor (gives “download progress” by disk growth)

    private func startModelMonitor() {
        stopModelMonitor()
        monitorTask = Task { @MainActor in
            while !Task.isCancelled {
                let bytes = WhisperModelInfo.currentBytesOnDisk()
                modelBytesOnDisk = bytes

                if let expected = modelExpectedBytes, expected > 0 {
                    let p = min(1.0, Double(bytes) / Double(expected))
                    modelProgress = p
                } else {
                    modelProgress = nil
                }

                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            }
        }
    }

    private func stopModelMonitor() {
        monitorTask?.cancel()
        monitorTask = nil
    }
}
