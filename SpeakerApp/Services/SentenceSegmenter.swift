import Foundation

struct AudioSegment: Hashable, Codable {
    let start: Double
    let end: Double
}

enum SentenceSegmenter {
    /// Splits into "sentences" based on end punctuation found in WordTiming.word.
    /// Uses timestamps from first and last word of each sentence.
    static func sentenceSegments(from words: [WordTiming]) -> [AudioSegment] {
        let sorted = words.sorted { $0.start < $1.start }
        guard !sorted.isEmpty else { return [] }

        // Sentence ends (include semicolon as you requested earlier for natural stops)
        let enders: Set<Character> = [".", "?", "!", "…", ";"]

        var segments: [AudioSegment] = []
        var currentStart = sorted[0].start
        var currentEnd = sorted[0].end

        for (idx, w) in sorted.enumerated() {
            currentEnd = max(currentEnd, w.end)

            let endsSentence = w.word.last.map { enders.contains($0) } ?? false
            if endsSentence {
                if currentEnd > currentStart {
                    segments.append(AudioSegment(start: currentStart, end: currentEnd))
                }
                // next sentence starts at next word (if any)
                if idx + 1 < sorted.count {
                    currentStart = sorted[idx + 1].start
                    currentEnd = sorted[idx + 1].end
                }
            }
        }

        // leftover tail (if last word didn’t end with punctuation)
        if segments.isEmpty || segments.last?.end != currentEnd {
            if currentEnd > currentStart {
                segments.append(AudioSegment(start: currentStart, end: currentEnd))
            }
        }

        // Filter tiny/invalid segments
        return segments
            .map { AudioSegment(start: max(0, $0.start), end: max($0.start, $0.end)) }
            .filter { ($0.end - $0.start) > 0.03 }
    }
}
