//
//  AudioPlaybackManager.swift
//  SpeakerApp
//

import Foundation
import AVFoundation
import Combine
#if os(iOS)
import AudioToolbox
#endif

@MainActor
final class AudioPlaybackManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isLoaded: Bool = false
    @Published private(set) var isPlaying: Bool = false

    // ✅ default = 10, hard limit 50
    @Published private(set) var loopCount: Int = 10

    // ✅ Partial play state
    @Published private(set) var isPartialPlaying: Bool = false
    @Published private(set) var partialIndex: Int = 0
    @Published private(set) var partialTotal: Int = 0

    @Published var errorMessage: String? = nil

    private var player: AVAudioPlayer?
    private var loadedURL: URL?

    private var partialTask: Task<Void, Never>?

    func loadIfNeeded(url: URL) {
        if loadedURL == url, player != nil { return }
        do { try load(url: url) } catch { errorMessage = error.localizedDescription }
    }

    private func load(url: URL) throws {
        errorMessage = nil

        guard FileManager.default.fileExists(atPath: url.path) else {
            isLoaded = false
            isPlaying = false
            player = nil
            loadedURL = nil
            errorMessage = "Stored audio file not found:\n\(url.lastPathComponent)"
            return
        }

        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif

        let p = try AVAudioPlayer(contentsOf: url)
        p.delegate = self
        p.prepareToPlay()

        player = p
        loadedURL = url
        isLoaded = true
        isPlaying = false

        applyLoopCount()
    }

    private func applyLoopCount() {
        let clamped = min(max(loopCount, 1), 50)
        loopCount = clamped
        player?.numberOfLoops = clamped - 1
    }

    // Tap repeat: +1 each time, wrap after 50 back to 1
    func cycleLoopCount() {
        let next = (loopCount >= 50) ? 1 : (loopCount + 1)
        loopCount = next
        applyLoopCount()
    }

    func togglePlay(url: URL) {
        // stop partial playback if user hits normal play
        stopPartialPlayback()

        loadIfNeeded(url: url)
        guard let p = player, isLoaded else { return }

        if p.isPlaying {
            p.pause()
            isPlaying = false
        } else {
            // normal full playback respects loopCount
            applyLoopCount()
            p.play()
            isPlaying = true
        }
    }

    func stop() {
        stopPartialPlayback()

        guard let p = player else { return }
        p.stop()
        p.currentTime = 0
        isPlaying = false
    }

    // MARK: - Partial playback (sentence by sentence)

    /// Plays the audio file sentence-by-sentence, based on word timestamps.
    /// Plays a short system sound between sentence cuts.
    func togglePartialPlay(url: URL, words: [WordTiming]) {
        if isPartialPlaying {
            stopPartialPlayback()
            stop()
            return
        }
        startPartialPlayback(url: url, words: words)
    }

    private func startPartialPlayback(url: URL, words: [WordTiming]) {
        stop() // stop any normal playback

        loadIfNeeded(url: url)
        guard let p = player, isLoaded else { return }

        let segments = SentenceSegmenter.sentenceSegments(from: words)
        guard !segments.isEmpty else {
            errorMessage = "No sentence segments found. (Try transcribing first.)"
            return
        }

        // Partial playback always plays ONCE per segment (no loops).
        p.numberOfLoops = 0

        isPartialPlaying = true
        partialIndex = 0
        partialTotal = segments.count
        errorMessage = nil

        partialTask?.cancel()
        partialTask = Task { [weak self] in
            guard let self else { return }

            for (idx, seg) in segments.enumerated() {
                if Task.isCancelled { break }

                await MainActor.run {
                    self.partialIndex = idx + 1
                }

                // Play that segment
                let ok = await self.playSegment(seg, with: url)
                if !ok || Task.isCancelled { break }

                // Beep between cuts (not after last one)
                if idx < segments.count - 1 {
                    await self.beep()
                    try? await Task.sleep(nanoseconds: 120_000_000) // small gap
                }
            }

            await MainActor.run {
                self.isPartialPlaying = false
                self.partialIndex = 0
                self.partialTotal = 0
                self.isPlaying = false
            }
        }
    }

    private func stopPartialPlayback() {
        partialTask?.cancel()
        partialTask = nil
        isPartialPlaying = false
        partialIndex = 0
        partialTotal = 0
    }

    private func playSegment(_ seg: AudioSegment, with url: URL) async -> Bool {
        loadIfNeeded(url: url)
        guard let p = player, isLoaded else { return false }

        // Clamp times
        let start = max(0, seg.start)
        let end = max(start, seg.end)
        let duration = end - start
        if duration < 0.03 { return true }

        // Start at the segment time
        p.stop()
        p.currentTime = start
        p.numberOfLoops = 0

        p.play()
        isPlaying = true

        // Wait for segment duration, then stop exactly at cut
        let nanos = UInt64(duration * 1_000_000_000)
        do {
            try await Task.sleep(nanoseconds: nanos)
        } catch {
            // cancelled
            p.stop()
            isPlaying = false
            return false
        }

        // Stop at end of segment
        p.pause()
        p.currentTime = end
        isPlaying = false
        return true
    }

    private func beep() async {
        #if os(iOS)
        // "Tock" system sound (works without bundling assets)
        AudioServicesPlaySystemSound(1104)
        #endif
    }

    // MARK: AVAudioPlayerDelegate
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.isPlaying = false }
    }
}
