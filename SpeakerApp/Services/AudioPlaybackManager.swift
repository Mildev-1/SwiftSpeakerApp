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

    // default = 10, hard limit 50
    @Published private(set) var loopCount: Int = 10

    // Partial play state
    @Published private(set) var isPartialPlaying: Bool = false
    @Published private(set) var partialIndex: Int = 0
    @Published private(set) var partialTotal: Int = 0

    // Highlight sentence currently played by tapping
    @Published private(set) var currentSentenceID: UUID? = nil

    @Published var errorMessage: String? = nil

    private var player: AVAudioPlayer?
    private var loadedURL: URL?

    private var partialTask: Task<Void, Never>?
    private var singleSegmentTask: Task<Void, Never>?

    // ✅ Padding to avoid clipping last phoneme / first consonant
    private let headPad: Double = 0.02   // 20ms earlier start
    private let tailPad: Double = 0.12   // 120ms extra at end (fixes “last letter cut”)

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

    func cycleLoopCount() {
        let next = (loopCount >= 50) ? 1 : (loopCount + 1)
        loopCount = next
        applyLoopCount()
    }

    func togglePlay(url: URL) {
        stopPartialPlayback()
        singleSegmentTask?.cancel()
        singleSegmentTask = nil
        currentSentenceID = nil

        loadIfNeeded(url: url)
        guard let p = player, isLoaded else { return }

        if p.isPlaying {
            p.pause()
            isPlaying = false
        } else {
            applyLoopCount()
            p.play()
            isPlaying = true
        }
    }

    func stop() {
        stopPartialPlayback()

        singleSegmentTask?.cancel()
        singleSegmentTask = nil
        currentSentenceID = nil

        guard let p = player else { return }
        p.stop()
        p.currentTime = 0
        isPlaying = false
    }

    // MARK: - Tap a sentence: play only its segment once

    func playSegmentOnce(url: URL, start: Double, end: Double, sentenceID: UUID? = nil) {
        stopPartialPlayback()

        singleSegmentTask?.cancel()
        singleSegmentTask = nil

        loadIfNeeded(url: url)
        guard let p = player, isLoaded else { return }

        let seg = adjustedSegment(start: start, end: end, playerDuration: p.duration)
        guard seg.duration > 0.03 else { return }

        currentSentenceID = sentenceID

        p.stop()
        p.numberOfLoops = 0
        p.currentTime = seg.start
        p.play()
        isPlaying = true

        singleSegmentTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: UInt64(seg.duration * 1_000_000_000))
            } catch {
                await MainActor.run {
                    self.isPlaying = false
                    self.currentSentenceID = nil
                }
                return
            }

            await MainActor.run {
                self.player?.pause()
                self.player?.currentTime = seg.end
                self.isPlaying = false
                self.currentSentenceID = nil
            }
        }
    }

    // MARK: - Partial playback (sentence-by-sentence)

    func togglePartialPlay(url: URL, words: [WordTiming]) {
        singleSegmentTask?.cancel()
        singleSegmentTask = nil
        currentSentenceID = nil

        if isPartialPlaying {
            stopPartialPlayback()
            stop()
            return
        }
        startPartialPlayback(url: url, words: words)
    }

    private func startPartialPlayback(url: URL, words: [WordTiming]) {
        stop()

        loadIfNeeded(url: url)
        guard let p = player, isLoaded else { return }

        let segments = SentenceSegmenter.sentenceSegments(from: words)
        guard !segments.isEmpty else {
            errorMessage = "No sentence segments found. (Try transcribing first.)"
            return
        }

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

                await MainActor.run { self.partialIndex = idx + 1 }

                let ok = await self.playSegment(seg, with: url)
                if !ok || Task.isCancelled { break }

                if idx < segments.count - 1 {
                    await self.beep()
                    try? await Task.sleep(nanoseconds: 120_000_000)
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

        let adj = adjustedSegment(start: seg.start, end: seg.end, playerDuration: p.duration)
        if adj.duration < 0.03 { return true }

        p.stop()
        p.currentTime = adj.start
        p.numberOfLoops = 0

        p.play()
        isPlaying = true

        do {
            try await Task.sleep(nanoseconds: UInt64(adj.duration * 1_000_000_000))
        } catch {
            p.stop()
            isPlaying = false
            return false
        }

        p.pause()
        p.currentTime = adj.end
        isPlaying = false
        return true
    }

    private func adjustedSegment(start: Double, end: Double, playerDuration: Double) -> (start: Double, end: Double, duration: Double) {
        // Apply pads and clamp to file duration
        let s = max(0, start - headPad)
        let e = min(playerDuration, max(s, end + tailPad))
        return (s, e, max(0, e - s))
    }

    private func beep() async {
        #if os(iOS)
        AudioServicesPlaySystemSound(1104) // "tock"
        #endif
    }

    // MARK: AVAudioPlayerDelegate
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.currentSentenceID = nil
        }
    }
}
