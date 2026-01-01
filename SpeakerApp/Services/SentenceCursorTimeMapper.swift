import Foundation

enum SentenceCursorTimeMapper {
    static let pauseEmoji = "⏸️"

    /// Given a sentence chunk and global word list, map current cursor location (in editedText)
    /// to a reasonable timestamp inside [chunk.start, chunk.end].
    static func cursorTime(
        editedText: String,
        cursorLocationUTF16: Int,
        chunk: SentenceChunk,
        allWords: [WordTiming]
    ) -> Double? {
        // pick words inside this sentence
        let eps = 0.02
        let words = allWords
            .filter { $0.start >= (chunk.start - eps) && $0.end <= (chunk.end + eps) }
            .sorted { $0.start < $1.start }

        guard !words.isEmpty else { return nil }

        // Build base sentence string from words using the same joining rules
        let base = joinWords(words.map { $0.word })
        let baseNSString = base as NSString

        // Convert cursor location in edited text -> "base" cursor by removing pause emojis before cursor
        let editedNSString = editedText as NSString
        let safeCursor = max(0, min(cursorLocationUTF16, editedNSString.length))
        let prefix = editedNSString.substring(to: safeCursor)
        let basePrefix = prefix.replacingOccurrences(of: pauseEmoji, with: "")
        let baseCursor = (basePrefix as NSString).length

        // Build per-word ranges in base string (best-effort)
        let ranges = computeWordRangesInBaseString(words: words, baseString: base)

        // Find word whose range contains cursor, else nearest by distance
        var bestIndex = 0
        var bestDistance = Int.max

        for (i, r) in ranges.enumerated() {
            if NSLocationInRange(baseCursor, r) { bestIndex = i; bestDistance = 0; break }
            let d = distance(from: baseCursor, to: r)
            if d < bestDistance { bestDistance = d; bestIndex = i }
        }

        // Choose boundary: if cursor is before the word range, use word.start; if after, use word.end
        let r = ranges[bestIndex]
        let w = words[bestIndex]

        if baseCursor <= r.location { return w.start }
        if baseCursor >= (r.location + r.length) { return w.end }
        return w.start
    }

    // MARK: - Helpers

    private static func distance(from x: Int, to r: NSRange) -> Int {
        if x < r.location { return r.location - x }
        if x > r.location + r.length { return x - (r.location + r.length) }
        return 0
    }

    // Rebuild base sentence string with punctuation joining rules
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

    /// Compute each word's NSRange inside baseString by scanning forward.
    /// This is robust enough because baseString was built from the same word tokens.
    private static func computeWordRangesInBaseString(words: [WordTiming], baseString: String) -> [NSRange] {
        let base = baseString as NSString
        var ranges: [NSRange] = []
        var searchFrom = 0

        for w in words {
            let token = w.word as NSString
            let tokenStr = token as String

            // Find next occurrence from current index
            let r = base.range(of: tokenStr, options: [], range: NSRange(location: searchFrom, length: base.length - searchFrom))
            if r.location != NSNotFound {
                ranges.append(r)
                searchFrom = r.location + r.length
            } else {
                // Fallback: empty range at current
                ranges.append(NSRange(location: min(searchFrom, base.length), length: 0))
            }
        }
        return ranges
    }
}
