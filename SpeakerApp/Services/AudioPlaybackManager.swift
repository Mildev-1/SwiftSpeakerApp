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
    @Published var errorMessage: String? = nil

    private var player: AVAudioPlayer?
    private var loadedURL: URL?

    private var partialTask: Task<Void, Never>?
    private var singleSegmentTask: Task<Void, Never>?

    private let headPad: Double = 0.02
    private let tailPad: Double = 0.12

    enum PartialPlaybackMode: Equatable {
        case beepBetweenCuts
        case repeatPractice(repeats: Int, silenceMultiplier: Double, sentencesPauseOnly: Bool)
    }

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
        cancelSingleSegment()
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
        cancelSingleSegment()
        currentSentenceID = nil

        guard let p = player else { return }
        p.stop()
        p.currentTime = 0
        isPlaying = false
    }

    private func cancelSingleSegment() {
        singleSegmentTask?.cancel()
        singleSegmentTask = nil
    }

    func playSegmentOnce(url: URL, start: Double, end: Double, sentenceID: String? = nil) {
        stopPartialPlayback()
        cancelSingleSegment()

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
        guard let p = player, isLoaded else { return }

        guard !chunks.isEmpty else {
            errorMessage = "No sentence chunks found. (Transcribe first.)"
            return
        }

        p.numberOfLoops = 0

        isPartialPlaying = true
        partialIndex = 0
        partialTotal = chunks.count
        errorMessage = nil

        partialTask?.cancel()
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

                // ✅ Decide split points
                let points: [Double]
                if sentencesOnly, case .repeatPractice = mode {
                    // Ignore in-sentence cuts: play whole sentence only
                    points = [chunk.start, chunk.end]
                } else {
                    let eps = 0.03
                    let cuts = (manualCutsBySentence[chunk.id] ?? [])
                        .filter { $0 > (chunk.start + eps) && $0 < (chunk.end - eps) }
                        .sorted()
                    var pts: [Double] = [chunk.start]
                    pts.append(contentsOf: cuts)
                    pts.append(chunk.end)
                    points = pts
                }

                for j in 0..<(points.count - 1) {
                    if Task.isCancelled { break }

                    let baseStart = points[j]
                    let baseEnd = points[j + 1]
                    let subID = SentenceSubchunkBuilder.subchunkID(sentenceID: chunk.id, start: baseStart, end: baseEnd)
                    let tune = fineTunesBySubchunk[subID] ?? SegmentFineTune()

                    var s = baseStart + tune.startOffset
                    var e = baseEnd + tune.endOffset
                    s = max(chunk.start, min(s, chunk.end))
                    e = max(chunk.start, min(e, chunk.end))
                    if e <= s { e = min(chunk.end, s + 0.05) }

                    let isLastSentence = (idx == chunks.count - 1)
                    let isLastPieceInSentence = (j == points.count - 2)
                    let isLastOverall = isLastSentence && isLastPieceInSentence

                    switch mode {
                    case .beepBetweenCuts:
                        let ok = await self.playSegment(start: s, end: e, with: url)
                        if !ok || Task.isCancelled { break }

                        if !isLastOverall {
                            await self.beep()
                            try? await Task.sleep(nanoseconds: 120_000_000)
                        }

                    case .repeatPractice:
                        let pieceDuration = max(0.03, e - s)
                        let silenceSeconds = max(0.05, (2.0 * pieceDuration) * practiceMult)

                        for _ in 0..<practiceRepeats {
                            if Task.isCancelled { break }
                            let ok = await self.playSegment(start: s, end: e, with: url)
                            if !ok || Task.isCancelled { break }
                            try? await Task.sleep(nanoseconds: UInt64(silenceSeconds * 1_000_000_000))
                        }

                        // Beep only at boundary between pieces/sentences (not after the last)
                        if !Task.isCancelled, !isLastOverall {
                            await self.beep()
                            try? await Task.sleep(nanoseconds: 120_000_000)
                        }
                    }
                }

                if Task.isCancelled { break }
            }

            await MainActor.run {
                self.isPartialPlaying = false
                self.partialIndex = 0
                self.partialTotal = 0
                self.isPlaying = false
                self.currentSentenceID = nil
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

    private func playSegment(start: Double, end: Double, with url: URL) async -> Bool {
        loadIfNeeded(url: url)
        guard let p = player, isLoaded else { return false }

        let adj = adjustedSegment(start: start, end: end, playerDuration: p.duration)
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
        let s = max(0, start - headPad)
        let e = min(playerDuration, max(s, end + tailPad))
        return (s, e, max(0, e - s))
    }

    private func beep() async {
        #if os(iOS)
        AudioServicesPlaySystemSound(1104)
        #endif
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.currentSentenceID = nil
        }
    }
}
