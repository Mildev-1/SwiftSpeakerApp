import Foundation

enum SentenceCursorTimeMapper {
    static let pauseEmoji = "⏸️"

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
        let basePrefix = prefix.replacingOccurrences(of: pauseEmoji, with: "")
        let baseCursor = (basePrefix as NSString).length

        let ranges = computeWordRangesInBaseString(words: words, baseString: base)

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

    // ✅ NEW: recompute ALL manual pause cut times from edited sentence text
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

            // We map time at the position right AFTER the emoji
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

    // MARK: - Helpers

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
            let r = base.range(of: tokenStr, options: [], range: NSRange(location: searchFrom, length: base.length - searchFrom))
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
