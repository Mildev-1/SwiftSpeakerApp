import Foundation

/// Estimates how long one Practice run will take, based on the *current* Practice settings.
/// This is read-only (no side effects) and is intended for UI previews only.
enum PracticeTimeEstimator {

    /// A small fixed pause used throughout practice after a "beep" cue.
    private static let beepPauseSeconds: Double = 0.12

    // Mirrors AudioPlaybackManager sentence padding behavior.
    private static let sentenceHeadPad: Double = 0.02
    private static let sentenceTailPad: Double = 0.12
    private static let sentenceFullTailPad: Double = 0.24 // tailPad * 2.0 (used only for whole-sentence practice)

    // Mirrors AudioPlaybackManager word padding behavior (precision words).
    private static let wordHeadPad: Double = 0.0
    private static let wordTailPad: Double = 0.0

    private struct Config {
        let head: Double
        let tail: Double
        let minDuration: Double
    }

    private static let sentenceConfig = Config(head: sentenceHeadPad, tail: sentenceTailPad, minDuration: 0.03)
    private static let fullSentenceConfig = Config(head: sentenceHeadPad, tail: sentenceFullTailPad, minDuration: 0.03)
    private static let wordConfig = Config(head: wordHeadPad, tail: wordTailPad, minDuration: 0.02)

    /// Estimate total seconds for the next session.
    ///
    /// - Parameters:
    ///   - mode: The effective practice mode (words / sentences / mixed / partial).
    ///   - chunks: The (already filtered) chunks that will be practiced in this run (e.g. flaggedOnly applied).
    ///   - manualCutsBySentence: Saved ⏸️ cut timestamps per sentence.
    ///   - fineTunesBySubchunk: Fine-tune offsets per subchunk id.
    ///   - wordSegments: Flat word segments (used by word-only mode).
    ///   - wordSegmentsBySentence: Word segments grouped per sentence (used by mixed mode).
    ///   - sentenceRepeats: Sentence-part repeats (repeat-practice).
    ///   - sentenceSilenceMultiplier: Sentence-part silence multiplier (repeat-practice).
    ///   - sentencesPauseOnly: If true, sentence practice ignores ⏸️ and plays whole sentence in one part.
    ///   - wordRepeats: Word repeats.
    ///   - wordSilenceMultiplier: Word silence multiplier.
    ///   - wordOuterLoops: Word-only mode loops the *whole segment list* this many times (mirrors AudioPlaybackManager.loopCount).
    static func estimateSeconds(
        mode: PracticeMode,
        chunks: [SentenceChunk],
        manualCutsBySentence: [String: [Double]],
        fineTunesBySubchunk: [String: SegmentFineTune],
        wordSegments: [AudioPlaybackManager.TimedSegment],
        wordSegmentsBySentence: [String: [AudioPlaybackManager.TimedSegment]],
        sentenceRepeats: Int,
        sentenceSilenceMultiplier: Double,
        sentencesPauseOnly: Bool,
        wordRepeats: Int,
        wordSilenceMultiplier: Double,
        wordOuterLoops: Int = 1
    ) -> Double {

        guard !chunks.isEmpty else { return 0 }

        // Clamp to the same UI limits used by playback.
        let sRepeats = min(max(sentenceRepeats, 1), 5)
        let sMult = min(max(sentenceSilenceMultiplier, 0.2), 15.0)

        let wRepeats = min(max(wordRepeats, 1), 5)
        let wMult = min(max(wordSilenceMultiplier, 0.2), 15.0)

        let outerLoops = max(1, wordOuterLoops)

        switch mode {
        case .words:
            return estimateWordsOnly(segments: wordSegments, repeats: wRepeats, mult: wMult, outerLoops: outerLoops)

        case .sentences:
            return estimateSentencesOnly(
                chunks: chunks,
                manualCutsBySentence: manualCutsBySentence,
                fineTunesBySubchunk: fineTunesBySubchunk,
                repeats: sRepeats,
                mult: sMult,
                sentencesPauseOnly: sentencesPauseOnly
            )

        case .mixed:
            return estimateMixed(
                chunks: chunks,
                manualCutsBySentence: manualCutsBySentence,
                fineTunesBySubchunk: fineTunesBySubchunk,
                wordSegmentsBySentence: wordSegmentsBySentence,
                wordRepeats: wRepeats,
                wordMult: wMult,
                sentenceRepeats: sRepeats,
                sentenceMult: sMult,
                sentencesPauseOnly: sentencesPauseOnly
            )

        case .partial:
            return estimatePartialCutsOnly(
                chunks: chunks,
                manualCutsBySentence: manualCutsBySentence,
                fineTunesBySubchunk: fineTunesBySubchunk
            )
        }
    }

    // MARK: - Words only

    private static func estimateWordsOnly(
        segments: [AudioPlaybackManager.TimedSegment],
        repeats: Int,
        mult: Double,
        outerLoops: Int
    ) -> Double {

        let segs = segments.sorted { $0.start < $1.start }
        guard !segs.isEmpty else { return 0 }

        var total: Double = 0

        for _ in 0..<outerLoops {
            for seg in segs {
                let playSeconds = segmentPlaySeconds(rawStart: seg.start, rawEnd: seg.end, config: wordConfig)
                let durForSilence = max(0.03, seg.duration)

                for _ in 0..<repeats {
                    total += playSeconds
                    // Model the intended practice pattern: add silence after each repetition.
                    total += durForSilence * mult
                }

                // Beep + tiny pause after each word segment.
                total += beepPauseSeconds
            }
        }
        return total
    }

    // MARK: - Sentences only (repeat practice)

    private static func estimateSentencesOnly(
        chunks: [SentenceChunk],
        manualCutsBySentence: [String: [Double]],
        fineTunesBySubchunk: [String: SegmentFineTune],
        repeats: Int,
        mult: Double,
        sentencesPauseOnly: Bool
    ) -> Double {

        var total: Double = 0

        for chunk in chunks {
            let points = cutPoints(for: chunk, manualCutsBySentence: manualCutsBySentence, sentencesPauseOnly: sentencesPauseOnly)

            let isWholeSentenceSingleSegment = sentencesPauseOnly && points.count == 2
            let cfg = isWholeSentenceSingleSegment ? fullSentenceConfig : sentenceConfig

            for partIndex in 0..<(points.count - 1) {
                let rawStart = points[partIndex]
                let rawEnd = points[partIndex + 1]

                let tuned = tunedSubchunkTimes(
                    rawStart: rawStart,
                    rawEnd: rawEnd,
                    chunk: chunk,
                    partIndex: partIndex,
                    pointsCount: points.count,
                    fineTunesBySubchunk: fineTunesBySubchunk
                )

                let playSeconds = segmentPlaySeconds(rawStart: tuned.start, rawEnd: tuned.end, config: cfg)
                let durForSilence = max(0.05, tuned.end - tuned.start)

                for _ in 0..<repeats {
                    total += playSeconds
                    total += durForSilence * mult
                }

                // Between parts: only when sentence is split into multiple parts.
                if !sentencesPauseOnly {
                    total += beepPauseSeconds
                }
            }

            // Between sentences: repeat-practice mode does a boundary beep/pause.
            total += beepPauseSeconds
        }

        return total
    }

    // MARK: - Partial (cuts only, no repeat practice)

    private static func estimatePartialCutsOnly(
        chunks: [SentenceChunk],
        manualCutsBySentence: [String: [Double]],
        fineTunesBySubchunk: [String: SegmentFineTune]
    ) -> Double {

        var total: Double = 0

        for chunk in chunks {
            let points = cutPoints(for: chunk, manualCutsBySentence: manualCutsBySentence, sentencesPauseOnly: false)

            for partIndex in 0..<(points.count - 1) {
                let rawStart = points[partIndex]
                let rawEnd = points[partIndex + 1]

                let tuned = tunedSubchunkTimes(
                    rawStart: rawStart,
                    rawEnd: rawEnd,
                    chunk: chunk,
                    partIndex: partIndex,
                    pointsCount: points.count,
                    fineTunesBySubchunk: fineTunesBySubchunk
                )

                total += segmentPlaySeconds(rawStart: tuned.start, rawEnd: tuned.end, config: sentenceConfig)

                // Beep/pause between cuts.
                if partIndex < (points.count - 2) {
                    total += beepPauseSeconds
                }
            }
        }

        return total
    }

    // MARK: - Mixed (words before each sentence part)

    private static func estimateMixed(
        chunks: [SentenceChunk],
        manualCutsBySentence: [String: [Double]],
        fineTunesBySubchunk: [String: SegmentFineTune],
        wordSegmentsBySentence: [String: [AudioPlaybackManager.TimedSegment]],
        wordRepeats: Int,
        wordMult: Double,
        sentenceRepeats: Int,
        sentenceMult: Double,
        sentencesPauseOnly: Bool
    ) -> Double {

        var total: Double = 0

        for chunk in chunks {
            let points = cutPoints(for: chunk, manualCutsBySentence: manualCutsBySentence, sentencesPauseOnly: sentencesPauseOnly)
            let allWords = (wordSegmentsBySentence[chunk.id] ?? []).sorted { $0.start < $1.start }

            for partIndex in 0..<(points.count - 1) {
                let rawStart = points[partIndex]
                let rawEnd = points[partIndex + 1]

                let tuned = tunedSubchunkTimes(
                    rawStart: rawStart,
                    rawEnd: rawEnd,
                    chunk: chunk,
                    partIndex: partIndex,
                    pointsCount: points.count,
                    fineTunesBySubchunk: fineTunesBySubchunk
                )

                // 1) Words within this sentence part (if any)
                if !allWords.isEmpty {
                    let partWords = allWords.filter {
                        let mid = ($0.start + $0.end) * 0.5
                        return mid >= tuned.start && mid <= tuned.end
                    }

                    for w in partWords {
                        let playSeconds = segmentPlaySeconds(rawStart: w.start, rawEnd: w.end, config: wordConfig)
                        let durForSilence = max(0.03, w.duration)

                        for _ in 0..<wordRepeats {
                            total += playSeconds
                            total += durForSilence * wordMult
                        }

                        total += beepPauseSeconds
                    }
                }

                // 2) Sentence part
                let playSeconds = segmentPlaySeconds(rawStart: tuned.start, rawEnd: tuned.end, config: sentenceConfig)
                let durForSilence = max(0.05, tuned.end - tuned.start)

                for _ in 0..<sentenceRepeats {
                    total += playSeconds
                    total += durForSilence * sentenceMult
                }

                // Between sentence parts in mixed mode: only if the sentence has manual pauses.
                if !sentencesPauseOnly && partIndex < (points.count - 2) {
                    total += beepPauseSeconds
                }
            }

            // Between sentences in mixed mode: repeat-practice boundary cue.
            total += beepPauseSeconds
        }

        return total
    }

    // MARK: - Helpers

    private static func segmentPlaySeconds(rawStart: Double, rawEnd: Double, config: Config) -> Double {
        let dur = max(0, rawEnd - rawStart)
        let padded = dur + config.head + config.tail
        return max(config.minDuration, padded)
    }

    private static func cutPoints(
        for chunk: SentenceChunk,
        manualCutsBySentence: [String: [Double]],
        sentencesPauseOnly: Bool
    ) -> [Double] {
        if sentencesPauseOnly {
            return [chunk.start, chunk.end]
        }
        let cuts = (manualCutsBySentence[chunk.id] ?? []).sorted()
        var points: [Double] = [chunk.start]
        points.append(contentsOf: cuts)
        points.append(chunk.end)
        return points
    }

    private static func tunedSubchunkTimes(
        rawStart: Double,
        rawEnd: Double,
        chunk: SentenceChunk,
        partIndex: Int,
        pointsCount: Int,
        fineTunesBySubchunk: [String: SegmentFineTune]
    ) -> (start: Double, end: Double) {

        let subchunkID = SentenceSubchunkBuilder.subchunkID(sentenceID: chunk.id, start: rawStart, end: rawEnd)
        let tune = fineTunesBySubchunk[subchunkID] ?? SegmentFineTune()

        var start = rawStart + tune.startOffset
        var end = rawEnd + tune.endOffset

        // Clamp, but allow edge parts to extend by up to the fine-tune limit (mirrors playback).
        let extra = 0.7
        let isFirstPart = (partIndex == 0)
        let isLastPart = (partIndex == pointsCount - 2)

        let minStart = isFirstPart ? max(0.0, chunk.start - extra) : chunk.start
        let maxEnd = isLastPart ? (chunk.end + extra) : chunk.end

        start = max(minStart, min(start, maxEnd))
        end = max(minStart, min(end, maxEnd))

        if end <= start {
            end = min(maxEnd, start + 0.05)
        }

        return (start, end)
    }
}
