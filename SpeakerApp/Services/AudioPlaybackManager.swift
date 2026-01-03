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

    /// generic timed segment for word-shadowing playback
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

    // Sentence/subchunk padding (existing behavior)
    private let headPad: Double = 0.02
    private let tailPad: Double = 0.12

    // Word precision padding
    private let wordHeadPad: Double = 0.00
    private let wordTailPad: Double = 0.00

    // MARK: - Segment config

    private struct SegmentPlaybackConfig {
        let head: Double
        let tail: Double
        let minDuration: Double
        let pollInterval: Double
        /// if true, sleep min(remaining, pollInterval) to reduce overshoot near end
        let useRemainingBasedPolling: Bool
        let label: String
    }

    private var sentenceConfig: SegmentPlaybackConfig {
        .init(head: headPad, tail: tailPad, minDuration: 0.03, pollInterval: 0.020, useRemainingBasedPolling: false, label: "SENTENCE")
    }

    private var wordConfig: SegmentPlaybackConfig {
        .init(head: wordHeadPad, tail: wordTailPad, minDuration: 0.02, pollInterval: 0.005, useRemainingBasedPolling: true, label: "WORD")
    }

    // MARK: - Debug logging (no behavior change)

    private enum LogLevel { case off, summary, verbose }

    #if DEBUG
    private let logLevel: LogLevel = .summary
    #else
    private let logLevel: LogLevel = .off
    #endif

    private func t(_ v: Double) -> String { String(format: "%.3f", v) }
    private func ms(_ v: Double) -> String { String(format: "%.1fms", v * 1000.0) }

    private func log(_ level: LogLevel = .summary, _ msg: @autoclosure () -> String) {
        guard logLevel != .off else { return }
        if logLevel == .summary && level == .verbose { return }
        let ts = String(format: "%.3f", CFAbsoluteTimeGetCurrent())
        print("🎧[\(ts)] \(msg())")
    }

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

            log(.summary, "LOAD ok duration=\(t(p.duration))s loops=\(loopCount)")
        } catch {
            errorMessage = "Failed to load audio: \(error.localizedDescription)"
            isLoaded = false
            log(.summary, "LOAD failed \(error.localizedDescription)")
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
            log(.summary, "TOGGLE play -> pause at=\(t(p.currentTime))s")
        } else {
            p.play()
            isPlaying = true
            isPaused = false
            log(.summary, "TOGGLE pause -> play at=\(t(p.currentTime))s")
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

        log(.summary, "STOP")
    }

    func togglePause() {
        guard isPlaying || isPartialPlaying || isPaused else { return }
        isPaused.toggle()

        if isPaused {
            player?.pause()
            isPlaying = false
            log(.summary, "PAUSE requested")
        } else {
            if isPartialPlaying == false {
                player?.play()
                isPlaying = true
            }
            log(.summary, "RESUME requested")
        }
    }

    private func clearPauseState() {
        isPaused = false
    }

    // MARK: - Single segment (used by edit sheets)

    /// Added `traceTag` (default) ONLY for logging.
    func playSegmentOnce(
        url: URL,
        start: Double,
        end: Double,
        sentenceID: String? = nil,
        traceTag: String = "EDIT"
    ) {
        stopPartialPlayback()
        cancelSingleSegment()
        clearPauseState()

        loadIfNeeded(url: url)
        guard let p = player, isLoaded else { return }

        // NOTE: existing behavior: adjust here (sentence pads) then playSegmentInternal adjusts again.
        let seg = adjustedSegment(start: start, end: end, playerDuration: p.duration, head: headPad, tail: tailPad)
        guard seg.duration > 0.03 else {
            log(.summary, "\(traceTag) playSegmentOnce SKIP tiny raw=[\(t(start)),\(t(end))] adj1=[\(t(seg.start)),\(t(seg.end))] dur=\(ms(seg.duration))")
            return
        }

        currentSentenceID = sentenceID

        log(.summary,
            "\(traceTag) playSegmentOnce raw=[\(t(start)),\(t(end))] adj1=[\(t(seg.start)),\(t(seg.end))] dur=\(ms(seg.duration)) head=\(ms(headPad)) tail=\(ms(tailPad))"
        )

        singleSegmentTask = Task { [weak self] in
            guard let self else { return }
            _ = await self.playSegmentInternal(
                start: seg.start,
                end: seg.end,
                with: url,
                config: self.sentenceConfig,
                traceTag: traceTag
            )
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
        stop()

        loadIfNeeded(url: url)
        guard let _ = player, isLoaded else { return }

        guard !chunks.isEmpty else {
            errorMessage = "No sentence chunks found. (Transcribe first.)"
            return
        }

        clearPauseState()

        player?.numberOfLoops = 0
        isPartialPlaying = true
        partialIndex = 0
        partialTotal = chunks.count

        partialTask = Task { [weak self] in
            guard let self else { return }

            let practiceRepeats: Int
            let practiceMult: Double
            let sentencesOnly: Bool
            let isRepeatPracticeMode: Bool

            switch mode {
            case .beepBetweenCuts:
                practiceRepeats = 1
                practiceMult = 1.0
                sentencesOnly = false
                isRepeatPracticeMode = false
            case .repeatPractice(let repeats, let silenceMultiplier, let sOnly):
                practiceRepeats = min(max(repeats, 1), 3)
                practiceMult = min(max(silenceMultiplier, 0.5), 2.0)
                sentencesOnly = sOnly
                isRepeatPracticeMode = true
            }

            log(.summary, "PRACTICE_SENT start chunks=\(chunks.count) reps=\(practiceRepeats) mult=\(practiceMult) sentencesOnly=\(sentencesOnly)")

            for (idx, chunk) in chunks.enumerated() {
                if Task.isCancelled { break }

                await MainActor.run {
                    self.partialIndex = idx + 1
                    self.currentSentenceID = chunk.id
                }

                // Build split points
                let points: [Double]
                if sentencesOnly, case .repeatPractice = mode {
                    points = [chunk.start, chunk.end]
                } else {
                    let cuts = (manualCutsBySentence[chunk.id] ?? []).sorted()
                    var arr = [chunk.start]
                    arr.append(contentsOf: cuts.filter { $0 > chunk.start && $0 < chunk.end })
                    arr.append(chunk.end)
                    points = arr
                }

                // Play each part
                for partIndex in 0..<(points.count - 1) {
                    if Task.isCancelled { break }

                    let rawStart = points[partIndex]
                    let rawEnd = points[partIndex + 1]

                    // Apply fine-tune offsets (same stable ID scheme as Edit)
                    let subchunkID = SentenceSubchunkBuilder.subchunkID(
                        sentenceID: chunk.id,
                        start: rawStart,
                        end: rawEnd
                    )
                    let tune = fineTunesBySubchunk[subchunkID] ?? SegmentFineTune()

                    var start = rawStart + tune.startOffset
                    var end = rawEnd + tune.endOffset

                    // ✅ NEW: clamp with edge-extension so ±0.7 works on first/last parts
                    let extra = 0.7
                    let isFirstPart = (partIndex == 0)
                    let isLastPart = (partIndex == points.count - 2)

                    let minStart = isFirstPart ? max(0.0, chunk.start - extra) : chunk.start
                    let maxEnd = isLastPart ? (chunk.end + extra) : chunk.end

                    start = max(minStart, min(start, maxEnd))
                    end = max(minStart, min(end, maxEnd))

                    if end <= start {
                        end = min(maxEnd, start + 0.05)
                    }

                    // repeats loop
                    for rep in 0..<practiceRepeats {
                        if Task.isCancelled { break }

                        log(.verbose,
                            "PRACTICE_SENT part rep=\(rep+1)/\(practiceRepeats) raw=[\(t(rawStart)),\(t(rawEnd))] tuned=[\(t(start)),\(t(end))] id=\(subchunkID)"
                        )

                        let ok = await self.playSegmentInternal(
                            start: start,
                            end: end,
                            with: url,
                            config: self.sentenceConfig,
                            traceTag: "PRACTICE_SENT"
                        )
                        if !ok { break }

                        // repeat-practice silence after each rep (already fixed)
                        if isRepeatPracticeMode {
                            let segDur = max(0.05, end - start)
                            log(.verbose, "PRACTICE_SENT silence=\(t(segDur * practiceMult))s")
                            _ = await self.sleepWithPause(seconds: segDur * practiceMult)
                        }
                    }

                    if Task.isCancelled { break }

                    // between-parts cue
                    if case .beepBetweenCuts = mode {
                        await self.beep()
                        _ = await self.sleepWithPause(seconds: 0.12)
                    } else {
                        if !(sentencesOnly) {
                            await self.beep()
                            _ = await self.sleepWithPause(seconds: 0.12)
                        }
                    }
                }

                // sentence boundary cue
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

            log(.summary, "PRACTICE_SENT done")
        }
    }


    // MARK: - Word-shadowing partial play (explicit segments)

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
        guard let _ = player, isLoaded else { return }

        let segs = segments.sorted { $0.start < $1.start }
        guard !segs.isEmpty else {
            errorMessage = "No word segments found."
            return
        }

        clearPauseState()

        player?.numberOfLoops = 0
        isPartialPlaying = true
        partialIndex = 0
        partialTotal = segs.count

        let r = min(max(repeats, 1), 5)
        let mult = min(max(silenceMultiplier, 0.2), 15.0)

        log(.summary, "PRACTICE_WORD start segs=\(segs.count) reps=\(r) mult=\(mult)")

        partialTask = Task { [weak self] in
            guard let self else { return }

            outer: for loop in 0..<max(1, loopCount) {
                self.log(.summary, "PRACTICE_WORD loop \(loop+1)/\(max(1, self.loopCount))")

                for (idx, seg) in segs.enumerated() {
                    if Task.isCancelled { break outer }

                    await MainActor.run {
                        self.partialIndex = idx + 1
                        self.currentSentenceID = seg.sentenceID
                    }

                    self.log(.summary, "PRACTICE_WORD seg \(idx+1)/\(segs.count) id=\(seg.id) raw=[\(self.t(seg.start)),\(self.t(seg.end))] dur=\(self.ms(seg.duration))")

                    for rep in 0..<r {
                        if Task.isCancelled { break outer }

                        self.log(.verbose, "PRACTICE_WORD rep \(rep+1)/\(r) seg=\(seg.id)")

                        let ok = await self.playSegmentInternal(
                            start: seg.start,
                            end: seg.end,
                            with: url,
                            config: self.wordConfig,
                            traceTag: "PRACTICE_WORD"
                        )
                        if !ok { break outer }

                        let dur = max(0.03, seg.duration)
                        self.log(.verbose, "PRACTICE_WORD silence after rep=\(rep+1) sleep=\(self.t(dur * mult))s")
                        _ = await self.sleepWithPause(seconds: dur * mult)
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

            self.log(.summary, "PRACTICE_WORD done")
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
                try await Task.sleep(nanoseconds: 50_000_000)
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

    // MARK: - Core segment playback (single engine, two configs)

    private func playSegmentInternal(
        start: Double,
        end: Double,
        with url: URL,
        config: SegmentPlaybackConfig,
        traceTag: String
    ) async -> Bool {
        loadIfNeeded(url: url)
        guard let p = player, isLoaded else { return false }

        let adj = adjustedSegment(
            start: start,
            end: end,
            playerDuration: p.duration,
            head: config.head,
            tail: config.tail
        )

        if adj.duration < config.minDuration {
            log(.verbose, "\(traceTag) \(config.label) SKIP tiny raw=[\(t(start)),\(t(end))] adj=[\(t(adj.start)),\(t(adj.end))] dur=\(ms(adj.duration))")
            return true
        }

        log(.summary,
            "\(traceTag) \(config.label) PLAY raw=[\(t(start)),\(t(end))] adj=[\(t(adj.start)),\(t(adj.end))] dur=\(ms(adj.duration)) head=\(ms(config.head)) tail=\(ms(config.tail)) poll=\(ms(config.pollInterval)) remPoll=\(config.useRemainingBasedPolling)"
        )

        p.stop()
        p.currentTime = adj.start
        p.numberOfLoops = 0

        p.play()
        isPlaying = true

        let targetEnd = adj.end
        var loops = 0
        let wallStart = CFAbsoluteTimeGetCurrent()

        while p.currentTime < targetEnd {
            loops += 1

            if Task.isCancelled {
                p.stop()
                isPlaying = false
                log(.summary, "\(traceTag) \(config.label) CANCEL at=\(t(p.currentTime)) target=\(t(targetEnd))")
                return false
            }

            if isPaused {
                p.pause()
                isPlaying = false

                let ok = await waitWhilePaused()
                if !ok {
                    p.stop()
                    isPlaying = false
                    log(.summary, "\(traceTag) \(config.label) ABORT during pause at=\(t(p.currentTime))")
                    return false
                }

                p.play()
                isPlaying = true
            }

            let step: Double
            if config.useRemainingBasedPolling {
                let remaining = max(0, targetEnd - p.currentTime)
                step = min(remaining, config.pollInterval)
            } else {
                step = config.pollInterval
            }

            do {
                try await Task.sleep(nanoseconds: UInt64(step * 1_000_000_000))
            } catch {
                p.stop()
                isPlaying = false
                log(.summary, "\(traceTag) \(config.label) SLEEP_ERR at=\(t(p.currentTime))")
                return false
            }
        }

        p.pause()
        isPlaying = false

        let wall = CFAbsoluteTimeGetCurrent() - wallStart
        let overshoot = p.currentTime - targetEnd

        log(.summary,
            "\(traceTag) \(config.label) DONE stopAt=\(t(p.currentTime)) target=\(t(targetEnd)) overshoot=\(ms(overshoot)) loops=\(loops) wall=\(t(wall))s"
        )

        return !Task.isCancelled
    }

    private func adjustedSegment(
        start: Double,
        end: Double,
        playerDuration: Double,
        head: Double,
        tail: Double
    ) -> (start: Double, end: Double, duration: Double) {
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
        }
    }

    /// Preview a word segment using the SAME playback policy as Practice word playback.
    /// No sentence padding, no double-adjustment. This is what you want for hard-word trimming.
    func playWordSegmentOnce(
        url: URL,
        start: Double,
        end: Double,
        sentenceID: String? = nil,
        traceTag: String = "EDIT_WORD_PRECISE"
    ) {
        stopPartialPlayback()
        cancelSingleSegment()
        clearPauseState()

        loadIfNeeded(url: url)
        guard isLoaded else { return }

        currentSentenceID = sentenceID

        singleSegmentTask = Task { [weak self] in
            guard let self else { return }
            _ = await self.playSegmentInternal(
                start: start,
                end: end,
                with: url,
                config: self.wordConfig,
                traceTag: traceTag
            )
        }
    }

    /// Preview a sentence segment using the SAME policy as Practice sentence playback
    /// (single adjustment with sentenceConfig; avoids double-padding from playSegmentOnce).
    func playSentenceSegmentOnce(
        url: URL,
        start: Double,
        end: Double,
        sentenceID: String? = nil,
        traceTag: String = "EDIT_PART"
    ) {
        stopPartialPlayback()
        cancelSingleSegment()
        clearPauseState()

        loadIfNeeded(url: url)
        guard isLoaded else { return }

        currentSentenceID = sentenceID

        singleSegmentTask = Task { [weak self] in
            guard let self else { return }
            _ = await self.playSegmentInternal(
                start: start,
                end: end,
                with: url,
                config: self.sentenceConfig,
                traceTag: traceTag
            )
        }
    }
}
