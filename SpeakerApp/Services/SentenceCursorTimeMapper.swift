import Foundation

enum SentenceCursorTimeMapper {
    static let pauseEmoji = "⏸️"
    static let rocketEmoji = "🚀"

    static func cursorTime(
        editedText: String,
        cursorLocationUTF16: Int,
        chunk: SentenceChunk,
        allWords: [WordTiming]
    ) -> Double? {
        let eps = 0.02
        let words = allWords
            .filter { $0.start >= (chunk.start - eps) && $0.end <= (chunk.end + eps) }
            .sorted { $0.start < $1.start }

        guard !words.isEmpty else { return nil }

        let base = joinWords(words.map { $0.word })

        let editedNSString = editedText as NSString
        let safeCursor = max(0, min(cursorLocationUTF16, editedNSString.length))
        let prefix = editedNSString.substring(to: safeCursor)

        // IMPORTANT:
        // rocket markers must NOT shift pause alignment, so strip BOTH markers here.
        let basePrefix = prefix
            .replacingOccurrences(of: pauseEmoji, with: "")
            .replacingOccurrences(of: rocketEmoji, with: "")

        let baseCursor = (basePrefix as NSString).length

        let ranges = computeWordRangesInBaseString(words: words, baseString: base)
        guard !ranges.isEmpty else { return nil }

        var bestIndex = 0
        var bestDistance = Int.max

        for (i, r) in ranges.enumerated() {
            if NSLocationInRange(baseCursor, r) { bestIndex = i; bestDistance = 0; break }
            let d = distance(from: baseCursor, to: r)
            if d < bestDistance { bestDistance = d; bestIndex = i }
        }

        let r = ranges[bestIndex]
        let w = words[bestIndex]

        if baseCursor <= r.location { return w.start }
        if baseCursor >= (r.location + r.length) { return w.end }
        return w.start
    }

    /// Recompute ALL manual pause cut times from edited sentence text.
    static func pauseTimesFromEditedText(
        editedText: String,
        chunk: SentenceChunk,
        allWords: [WordTiming]
    ) -> [Double] {
        let ns = editedText as NSString
        let emoji = pauseEmoji as NSString
        let emojiLen = emoji.length

        var times: [Double] = []

        var searchRange = NSRange(location: 0, length: ns.length)
        while true {
            let found = ns.range(of: pauseEmoji, options: [], range: searchRange)
            if found.location == NSNotFound { break }

            // Map time at the position right AFTER the emoji
            let cursor = found.location + emojiLen
            if let t = cursorTime(
                editedText: editedText,
                cursorLocationUTF16: cursor,
                chunk: chunk,
                allWords: allWords
            ) {
                times.append(t)
            }

            let nextLoc = found.location + max(found.length, 1)
            if nextLoc >= ns.length { break }
            searchRange = NSRange(location: nextLoc, length: ns.length - nextLoc)
        }

        // de-dupe within 30ms
        let eps = 0.03
        let sorted = times.sorted()
        var uniq: [Double] = []
        for t in sorted {
            if uniq.contains(where: { abs($0 - t) < eps }) { continue }
            uniq.append(t)
        }
        return uniq
    }

    /// Extract hard words:
    /// - 🚀 marks the NEXT 1 word (existing behavior)
    /// - 🚀🚀 marks the NEXT 2 words
    /// - 🚀🚀🚀 (or more) marks the NEXT 3 words (capped at 3)
    ///
    /// Returned segments are stable (ID derived from start/end ms) and can be fine-tuned separately.
    static func hardWordSegmentsFromEditedText(
        editedText: String,
        chunk: SentenceChunk,
        allWords: [WordTiming]
    ) -> [HardWordSegment] {
        let eps = 0.02
        let words = allWords
            .filter { $0.start >= (chunk.start - eps) && $0.end <= (chunk.end + eps) }
            .sorted { $0.start < $1.start }

        guard !words.isEmpty else { return [] }

        let base = joinWords(words.map { $0.word })
        let ranges = computeWordRangesInBaseString(words: words, baseString: base)
        guard !ranges.isEmpty else { return [] }

        let ns = editedText as NSString

        var out: [HardWordSegment] = []
        var seen: Set<String> = []

        var searchRange = NSRange(location: 0, length: ns.length)
        while true {
            let found = ns.range(of: rocketEmoji, options: [], range: searchRange)
            if found.location == NSNotFound { break }

            // ✅ Robust: compute the rocket run using actual matched lengths, not emojiLen math.
            let run = rocketRun(in: ns, from: found.location)
            let requestedCount = max(run.count, 1)
            let bundleCount = min(requestedCount, 4)   // ✅ up to 4 words

            // Cursor right after the full rocket run (UTF16 index)
            let cursorUTF16 = run.endLocation

            let baseCursor = baseCursorLocation(
                editedText: editedText,
                cursorLocationUTF16: cursorUTF16
            )

            let startIdx = hardWordIndex(baseCursor: baseCursor, ranges: ranges)
            let safeStart = min(max(0, startIdx), words.count - 1)

            // If not enough words remain, just take what's available
            let safeEnd = min(words.count - 1, safeStart + bundleCount - 1)

            let startWord = words[safeStart]
            let endWord = words[safeEnd]

            let segStart = startWord.start
            let segEnd = endWord.end

            let label: String
            if safeStart == safeEnd {
                label = startWord.word
            } else {
                let toks = words[safeStart...safeEnd].map { $0.word }
                label = joinWords(toks)
            }

            let id = HardWordSegment.makeID(sentenceID: chunk.id, start: segStart, end: segEnd)
            if !seen.contains(id) {
                out.append(
                    HardWordSegment(
                        sentenceID: chunk.id,
                        index: out.count,
                        start: segStart,
                        end: segEnd,
                        word: label
                    )
                )
                seen.insert(id)
            }

            // ✅ Advance search past the entire rocket run (robust)
            let nextLoc = max(run.endLocation, found.location + max(found.length, 1))
            if nextLoc >= ns.length { break }
            searchRange = NSRange(location: nextLoc, length: ns.length - nextLoc)
        }

        return out
    }



    // MARK: - Helpers

    /// Count how many 🚀 occur consecutively starting at `location` (UTF16 indexing, via NSString).
    private static func rocketRunLength(in ns: NSString, from location: Int, emojiLen: Int) -> Int {
        guard location >= 0, location < ns.length else { return 0 }
        guard emojiLen > 0 else { return 0 }

        var count = 0
        var loc = location

        while loc + emojiLen <= ns.length {
            let r = NSRange(location: loc, length: emojiLen)
            let slice = ns.substring(with: r)
            if slice == rocketEmoji {
                count += 1
                loc += emojiLen
            } else {
                break
            }
        }

        return count
    }
    
    /// Robustly count consecutive 🚀 starting at a UTF16 location.
    /// Uses actual matched range lengths (handles variation selectors / pasted emojis).
    private static func rocketRun(in ns: NSString, from location: Int) -> (count: Int, endLocation: Int) {
        guard location >= 0, location < ns.length else { return (0, location) }

        var count = 0
        var loc = location

        while loc < ns.length {
            let r = ns.range(of: rocketEmoji, options: [], range: NSRange(location: loc, length: ns.length - loc))
            guard r.location == loc, r.length > 0 else { break }
            count += 1
            loc += r.length
        }

        return (count, loc)
    }

    private static func baseCursorLocation(editedText: String, cursorLocationUTF16: Int) -> Int {
        let editedNSString = editedText as NSString
        let safeCursor = max(0, min(cursorLocationUTF16, editedNSString.length))
        let prefix = editedNSString.substring(to: safeCursor)

        // Strip markers so they don't affect alignment.
        let stripped = prefix
            .replacingOccurrences(of: pauseEmoji, with: "")
            .replacingOccurrences(of: rocketEmoji, with: "")

        return (stripped as NSString).length
    }

    /// For hard-word selection: pick the next word after cursor.
    /// If cursor is inside a word, pick that word.
    private static func hardWordIndex(baseCursor: Int, ranges: [NSRange]) -> Int {
        guard !ranges.isEmpty else { return 0 }

        for (i, r) in ranges.enumerated() {
            // cursor before this word => next word
            if baseCursor <= r.location { return i }
            // cursor inside this word => this word
            if NSLocationInRange(baseCursor, r) { return i }
        }
        return max(0, ranges.count - 1)
    }

    private static func distance(from x: Int, to r: NSRange) -> Int {
        if x < r.location { return r.location - x }
        if x > r.location + r.length { return x - (r.location + r.length) }
        return 0
    }

    private static let noSpaceBefore: Set<Character> = [".", ",", "?", "!", "…", ";", ":", ")", "]", "}", "\"", "”", "’"]

    private static func joinWords(_ tokens: [String]) -> String {
        var out = ""
        for t in tokens where !t.isEmpty {
            if out.isEmpty { out = t; continue }
            if let first = t.first, noSpaceBefore.contains(first) {
                out += t
            } else {
                out += " " + t
            }
        }
        return out
    }

    private static func computeWordRangesInBaseString(words: [WordTiming], baseString: String) -> [NSRange] {
        let base = baseString as NSString
        var ranges: [NSRange] = []
        var searchFrom = 0

        for w in words {
            let tokenStr = w.word
            let r = base.range(
                of: tokenStr,
                options: [],
                range: NSRange(location: searchFrom, length: max(0, base.length - searchFrom))
            )
            if r.location != NSNotFound {
                ranges.append(r)
                searchFrom = r.location + r.length
            } else {
                ranges.append(NSRange(location: min(searchFrom, base.length), length: 0))
            }
        }
        return ranges
    }
}
