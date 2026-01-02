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
    @Published private(set) var loopCount: Int = 10

    @Published private(set) var isPartialPlaying: Bool = false
    @Published private(set) var partialIndex: Int = 0
    @Published private(set) var partialTotal: Int = 0
    @Published private(set) var currentSentenceID: String? = nil

    @Published private(set) var isPaused: Bool = false
    @Published var errorMessage: String? = nil

    /// NEW: generic timed segment for word-shadowing playback
    struct TimedSegment: Identifiable, Hashable {
        let id: String
        let sentenceID: String?
        let start: Double
        let end: Double

        init(sentenceID: String?, start: Double, end: Double) {
            self.sentenceID = sentenceID
            self.start = start
            self.end = end
            let s = Int((start * 1000).rounded())
            let e = Int((end * 1000).rounded())
            self.id = "\(sentenceID ?? "nil")|\(s)_\(e)"
        }

        var duration: Double { max(0, end - start) }
    }

    enum PartialPlaybackMode: Hashable {
        case beepBetweenCuts
        case repeatPractice(repeats: Int, silenceMultiplier: Double, sentencesPauseOnly: Bool)
    }

    private var player: AVAudioPlayer?
    private var partialTask: Task<Void, Never>?
    private var singleSegmentTask: Task<Void, Never>?

    // Sentence/subchunk padding (existing)
    private let headPad: Double = 0.02
    private let tailPad: Double = 0.12

    // Word precision padding (NEW)
    private let wordHeadPad: Double = 0.00
    private let wordTailPad: Double = 0.02

    // MARK: - Loading

    func loadIfNeeded(url: URL) {
        if isLoaded { return }
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.prepareToPlay()
            player = p

            isLoaded = true
            isPlaying = false
            isPaused = false

            applyLoopCount()
        } catch {
            errorMessage = "Failed to load audio: \(error.localizedDescription)"
            isLoaded = false
        }
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

    // MARK: - Basic play/pause/stop

    func togglePlay(url: URL) {
        cancelSingleSegment()
        stopPartialPlayback()
        clearPauseState()

        loadIfNeeded(url: url)
        guard let p = player, isLoaded else { return }

        if p.isPlaying {
            p.pause()
            isPlaying = false
            isPaused = true
        } else {
            p.play()
            isPlaying = true
            isPaused = false
        }
    }

    func stop() {
        cancelSingleSegment()
        stopPartialPlayback()

        player?.stop()
        player?.currentTime = 0

        isPlaying = false
        isPaused = false
        currentSentenceID = nil
    }

    /// ✅ Pauses or resumes current playback (full or partial).
    /// Works during partial-play segment loops and silence waits.
    func togglePause() {
        guard isPlaying || isPartialPlaying || isPaused else { return }
        isPaused.toggle()

        if isPaused {
            player?.pause()
            isPlaying = false
        } else {
            // Resume only if we are in a playing context
            // (partial loop will restart the player as needed)
            if isPartialPlaying == false {
                player?.play()
                isPlaying = true
            }
        }
    }

    private func clearPauseState() {
        isPaused = false
    }

    // MARK: - Single segment (used by edit sheets)

    func playSegmentOnce(url: URL, start: Double, end: Double, sentenceID: String? = nil) {
        stopPartialPlayback()
        cancelSingleSegment()
        clearPauseState()

        loadIfNeeded(url: url)
        guard let p = player, isLoaded else { return }

        let seg = adjustedSegment(start: start, end: end, playerDuration: p.duration, head: headPad, tail: tailPad)
        guard seg.duration > 0.03 else { return }

        currentSentenceID = sentenceID

        singleSegmentTask = Task { [weak self] in
            guard let self else { return }
            _ = await self.playSegment(start: seg.start, end: seg.end, with: url)
        }
    }

    private func cancelSingleSegment() {
        singleSegmentTask?.cancel()
        singleSegmentTask = nil
    }

    // MARK: - Existing sentence/subchunk partial play

    func togglePartialPlay(
        url: URL,
        chunks: [SentenceChunk],
        manualCutsBySentence: [String: [Double]],
        fineTunesBySubchunk: [String: SegmentFineTune],
        mode: PartialPlaybackMode = .beepBetweenCuts
    ) {
        cancelSingleSegment()
        currentSentenceID = nil

        if isPartialPlaying {
            stopPartialPlayback()
            stop()
            return
        }

        startPartialPlayback(
            url: url,
            chunks: chunks,
            manualCutsBySentence: manualCutsBySentence,
            fineTunesBySubchunk: fineTunesBySubchunk,
            mode: mode
        )
    }

    private func startPartialPlayback(
        url: URL,
        chunks: [SentenceChunk],
        manualCutsBySentence: [String: [Double]],
        fineTunesBySubchunk: [String: SegmentFineTune],
        mode: PartialPlaybackMode
    ) {
        stop() // also clears pause state

        loadIfNeeded(url: url)
        guard let p = player, isLoaded else { return }

        guard !chunks.isEmpty else {
            errorMessage = "No sentence chunks found. (Transcribe first.)"
            return
        }

        clearPauseState()

        p.numberOfLoops = 0
        isPartialPlaying = true
        partialIndex = 0
        partialTotal = chunks.count

        partialTask = Task { [weak self] in
            guard let self else { return }

            let practiceRepeats: Int
            let practiceMult: Double
            let sentencesOnly: Bool

            switch mode {
            case .beepBetweenCuts:
                practiceRepeats = 1
                practiceMult = 1.0
                sentencesOnly = false
            case .repeatPractice(let repeats, let silenceMultiplier, let sOnly):
                practiceRepeats = min(max(repeats, 1), 3)
                practiceMult = min(max(silenceMultiplier, 0.5), 2.0)
                sentencesOnly = sOnly
            }

            for (idx, chunk) in chunks.enumerated() {
                if Task.isCancelled { break }

                await MainActor.run {
                    self.partialIndex = idx + 1
                    self.currentSentenceID = chunk.id
                }

                // split points
                let points: [Double]
                if sentencesOnly, case .repeatPractice = mode {
                    points = [chunk.start, chunk.end]
                } else {
                    // Build points from manual cuts + fine tune (existing behavior)
                    let cuts = (manualCutsBySentence[chunk.id] ?? []).sorted()
                    var arr = [chunk.start]
                    arr.append(contentsOf: cuts.filter { $0 > chunk.start && $0 < chunk.end })
                    arr.append(chunk.end)
                    points = arr
                }

                // Play each part with repeats
                for partIndex in 0..<(points.count - 1) {
                    if Task.isCancelled { break }

                    let rawStart = points[partIndex]
                    let rawEnd = points[partIndex + 1]

                    // Apply fine-tune if we can map an id (existing code uses SentenceSubchunkBuilder ids;
                    // here we just play raw segments if sentencesOnly)
                    var start = rawStart
                    var end = rawEnd

                    // Repeats loop
                    for rep in 0..<practiceRepeats {
                        if Task.isCancelled { break }

                        let ok = await self.playSegment(start: start, end: end, with: url)
                        if !ok { break }

                        if rep < (practiceRepeats - 1) {
                            // silence gap proportional to segment duration
                            let segDur = max(0.05, end - start)
                            _ = await self.sleepWithPause(seconds: segDur * practiceMult)
                        }
                    }

                    if Task.isCancelled { break }

                    if case .beepBetweenCuts = mode {
                        await self.beep()
                        _ = await self.sleepWithPause(seconds: 0.12)
                    } else {
                        // if sentencesPauseOnly: no beep between parts
                        if !(sentencesOnly) {
                            await self.beep()
                            _ = await self.sleepWithPause(seconds: 0.12)
                        }
                    }
                }

                // sentence boundary pause
                if case .repeatPractice = mode {
                    await self.beep()
                    _ = await self.sleepWithPause(seconds: 0.12)
                }
            }

            await MainActor.run {
                self.isPartialPlaying = false
                self.partialIndex = 0
                self.partialTotal = 0
            }
        }
    }

    // MARK: - ✅ NEW: Word-shadowing partial play (explicit segments)

    func togglePartialPlayWordSegments(
        url: URL,
        segments: [TimedSegment],
        repeats: Int,
        silenceMultiplier: Double
    ) {
        cancelSingleSegment()
        currentSentenceID = nil

        if isPartialPlaying {
            stopPartialPlayback()
            stop()
            return
        }

        startWordSegmentsPlayback(
            url: url,
            segments: segments,
            repeats: repeats,
            silenceMultiplier: silenceMultiplier
        )
    }

    private func startWordSegmentsPlayback(
        url: URL,
        segments: [TimedSegment],
        repeats: Int,
        silenceMultiplier: Double
    ) {
        stop()

        loadIfNeeded(url: url)
        guard let p = player, isLoaded else { return }

        let segs = segments.sorted { $0.start < $1.start }
        guard !segs.isEmpty else {
            errorMessage = "No word segments found."
            return
        }

        clearPauseState()

        p.numberOfLoops = 0
        isPartialPlaying = true
        partialIndex = 0
        partialTotal = segs.count

        let r = min(max(repeats, 1), 5)
        let mult = min(max(silenceMultiplier, 0.2), 6.0)

        partialTask = Task { [weak self] in
            guard let self else { return }

            outer: for _ in 0..<max(1, loopCount) {
                for (idx, seg) in segs.enumerated() {
                    if Task.isCancelled { break outer }

                    await MainActor.run {
                        self.partialIndex = idx + 1
                        self.currentSentenceID = seg.sentenceID
                    }

                    // repeats
                    for rep in 0..<r {
                        if Task.isCancelled { break outer }

                        let ok = await self.playWordSegment(start: seg.start, end: seg.end, with: url)
                        if !ok { break outer }

                        if rep < (r - 1) {
                            let dur = max(0.03, seg.duration)
                            _ = await self.sleepWithPause(seconds: dur * mult)
                        }
                    }

                    if Task.isCancelled { break outer }
                    await self.beep()
                    _ = await self.sleepWithPause(seconds: 0.12)
                }
            }

            await MainActor.run {
                self.isPartialPlaying = false
                self.partialIndex = 0
                self.partialTotal = 0
            }
        }
    }

    // MARK: - Stop partial

    private func stopPartialPlayback() {
        partialTask?.cancel()
        partialTask = nil
        isPartialPlaying = false
        partialIndex = 0
        partialTotal = 0
        isPaused = false
    }

    // MARK: - Pause-aware helpers

    private func waitWhilePaused() async -> Bool {
        while isPaused {
            if Task.isCancelled { return false }
            do {
                try await Task.sleep(nanoseconds: 50_000_000) // 50ms
            } catch {
                return false
            }
        }
        return !Task.isCancelled
    }

    private func sleepWithPause(seconds: Double) async -> Bool {
        var remaining = max(0, seconds)
        while remaining > 0 {
            if Task.isCancelled { return false }
            if isPaused {
                let ok = await waitWhilePaused()
                if !ok { return false }
            }
            let step = min(remaining, 0.05)
            do {
                try await Task.sleep(nanoseconds: UInt64(step * 1_000_000_000))
            } catch {
                return false
            }
            remaining -= step
        }
        return !Task.isCancelled
    }

    // MARK: - Core segment playback (pause-aware)

    private func playSegment(start: Double, end: Double, with url: URL) async -> Bool {
        loadIfNeeded(url: url)
        guard let p = player, isLoaded else { return false }

        let adj = adjustedSegment(start: start, end: end, playerDuration: p.duration, head: headPad, tail: tailPad)
        if adj.duration < 0.03 { return true }

        p.stop()
        p.currentTime = adj.start
        p.numberOfLoops = 0

        p.play()
        isPlaying = true

        let targetEnd = adj.end
        while p.currentTime < targetEnd {
            if Task.isCancelled {
                p.stop()
                isPlaying = false
                return false
            }

            if isPaused {
                p.pause()
                isPlaying = false

                let ok = await waitWhilePaused()
                if !ok {
                    p.stop()
                    isPlaying = false
                    return false
                }

                p.play()
                isPlaying = true
            }

            do {
                try await Task.sleep(nanoseconds: 20_000_000) // 20ms
            } catch {
                p.stop()
                isPlaying = false
                return false
            }
        }

        p.pause()
        isPlaying = false
        return !Task.isCancelled
    }

    /// Word-precision variant (smaller padding)
    private func playWordSegment(start: Double, end: Double, with url: URL) async -> Bool {
        loadIfNeeded(url: url)
        guard let p = player, isLoaded else { return false }

        let adj = adjustedSegment(start: start, end: end, playerDuration: p.duration, head: wordHeadPad, tail: wordTailPad)
        if adj.duration < 0.02 { return true }

        p.stop()
        p.currentTime = adj.start
        p.numberOfLoops = 0

        p.play()
        isPlaying = true

        let targetEnd = adj.end
        while p.currentTime < targetEnd {
            if Task.isCancelled {
                p.stop()
                isPlaying = false
                return false
            }

            if isPaused {
                p.pause()
                isPlaying = false

                let ok = await waitWhilePaused()
                if !ok {
                    p.stop()
                    isPlaying = false
                    return false
                }

                p.play()
                isPlaying = true
            }

            do {
                try await Task.sleep(nanoseconds: 15_000_000) // 15ms
            } catch {
                p.stop()
                isPlaying = false
                return false
            }
        }

        p.pause()
        isPlaying = false
        return !Task.isCancelled
    }

    private func adjustedSegment(start: Double, end: Double, playerDuration: Double, head: Double, tail: Double) -> (start: Double, end: Double, duration: Double) {
        let s = max(0, start - head)
        let e = min(playerDuration, max(s, end + tail))
        return (s, e, max(0, e - s))
    }

    private func beep() async {
        #if os(iOS)
        AudioServicesPlaySystemSound(1104)
        #endif
    }

    // MARK: - AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.currentSentenceID = nil
            // Don't auto-clear partial flags here; partial task controls closing.
        }
    }
}
