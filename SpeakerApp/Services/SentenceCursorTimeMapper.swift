import Foundation

enum SentenceCursorTimeMapper {
    static let pauseEmoji = "⏸️"
    static let rocketEmoji = "🚀"

    // MARK: - Public API

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

        // Work in "stripped text space" (no markers / no variation selectors)
        let strippedFull = stripMarkersAndVS(editedText)
        let ranges = computeWordRangesInString(words: words, in: strippedFull)
        guard !ranges.isEmpty else { return nil }

        let ns = editedText as NSString
        let safeCursor = max(0, min(cursorLocationUTF16, ns.length))
        let prefix = ns.substring(to: safeCursor)

        let strippedPrefix = stripMarkersAndVS(prefix)
        let baseCursor = (strippedPrefix as NSString).length

        // Choose nearest word range
        var bestIndex = 0
        var bestDistance = Int.max

        for (i, r) in ranges.enumerated() {
            if NSLocationInRange(baseCursor, r) { bestIndex = i; bestDistance = 0; break }
            let d = distance(from: baseCursor, to: r)
            if d < bestDistance { bestDistance = d; bestIndex = i }
        }

        let r = ranges[bestIndex]
        let w = words[bestIndex]

        // Same behavior as before
        if baseCursor <= r.location { return w.start }
        if baseCursor >= (r.location + r.length) { return w.end }
        return w.start
    }

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

            // Cursor right after the pause marker
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

    /// Hard words:
    /// - 🚀 => next 1 word
    /// - 🚀🚀 => next 2
    /// - 🚀🚀🚀 => next 3
    /// - 🚀🚀🚀🚀 (or more) => next 4 (cap at 4)
    ///
    /// Uses stripped-text cursor mapping so "next word" is stable even with emoji variants and spacing.
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

        // Work in "stripped text space" (no markers / no variation selectors)
        let strippedFull = stripMarkersAndVS(editedText)
        let ranges = computeWordRangesInString(words: words, in: strippedFull)
        guard !ranges.isEmpty else { return [] }

        let ns = editedText as NSString

        var out: [HardWordSegment] = []
        var seen: Set<String> = []

        var searchRange = NSRange(location: 0, length: ns.length)
        while true {
            let found = ns.range(of: rocketEmoji, options: [], range: searchRange)
            if found.location == NSNotFound { break }

            // Count a run of rockets robustly (handles 🚀️ too)
            let run = rocketRun(in: ns, from: found.location)

            let requestedCount = max(run.count, 1)
            let bundleCount = min(requestedCount, 4)

            // Cursor after rockets and after whitespace
            let cursorAfterMarkers = skipWhitespace(in: ns, from: run.endLocation)

            // Map cursor into stripped space
            let prefix = ns.substring(to: max(0, min(cursorAfterMarkers, ns.length)))
            let strippedPrefix = stripMarkersAndVS(prefix)
            let baseCursor = (strippedPrefix as NSString).length

            // Pick the next word in stripped space
            let startIdx = hardWordIndex(baseCursor: baseCursor, ranges: ranges)
            let safeStart = min(max(0, startIdx), words.count - 1)

            // If not enough words remain, just take all remaining
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

            // Advance search past the rocket run
            let nextLoc = max(run.endLocation, found.location + max(found.length, 1))
            if nextLoc >= ns.length { break }
            searchRange = NSRange(location: nextLoc, length: ns.length - nextLoc)
        }

        return out
    }

    // MARK: - Helpers (rocket parsing + cursor mapping)

    /// Remove pause/rocket markers AND variation selectors (FE0F/FE0E).
    /// This keeps cursor mapping stable across emoji variants and pasted text.
    private static func stripMarkersAndVS(_ s: String) -> String {
        var out = s
        out = out
            .replacingOccurrences(of: "🚀️", with: "")
            .replacingOccurrences(of: "🚀", with: "")
            .replacingOccurrences(of: "⏸️", with: "")
            .replacingOccurrences(of: "⏸", with: "")
            .replacingOccurrences(of: "\u{FE0F}", with: "")
            .replacingOccurrences(of: "\u{FE0E}", with: "")
        return out
    }

    /// Count consecutive rockets starting at a UTF16 location.
    /// Consumes "🚀️" and "🚀" as markers.
    private static func rocketRun(in ns: NSString, from location: Int) -> (count: Int, endLocation: Int) {
        guard location >= 0, location < ns.length else { return (0, location) }

        let variants: [String] = ["🚀️", "🚀"]

        var count = 0
        var loc = location

        while loc < ns.length {
            var matchedLen: Int? = nil

            for v in variants {
                let r = ns.range(of: v, options: [], range: NSRange(location: loc, length: ns.length - loc))
                if r.location == loc, r.length > 0 {
                    matchedLen = r.length
                    break
                }
            }

            guard let len = matchedLen else { break }
            count += 1
            loc += len
        }

        return (count, loc)
    }

    private static func skipWhitespace(in ns: NSString, from location: Int) -> Int {
        var loc = max(0, min(location, ns.length))
        while loc < ns.length {
            let ch = ns.character(at: loc)
            guard let scalar = UnicodeScalar(ch) else { break }
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                loc += 1
            } else {
                break
            }
        }
        return loc
    }

    /// Build ranges by searching the *actual stripped edited sentence*.
    /// This avoids drift caused by `joinWords(...)` when WordTiming.word has leading spaces.
    private static func computeWordRangesInString(words: [WordTiming], in strippedFull: String) -> [NSRange] {
        let base = strippedFull as NSString
        var ranges: [NSRange] = []
        var searchFrom = 0

        for w in words {
            let token = w.word.trimmingCharacters(in: .whitespacesAndNewlines)
            if token.isEmpty {
                ranges.append(NSRange(location: min(searchFrom, base.length), length: 0))
                continue
            }

            let r = base.range(
                of: token,
                options: [],
                range: NSRange(location: searchFrom, length: max(0, base.length - searchFrom))
            )

            if r.location != NSNotFound {
                ranges.append(r)
                searchFrom = r.location + r.length
            } else {
                // fallback: keep ordering even if not found
                ranges.append(NSRange(location: min(searchFrom, base.length), length: 0))
            }
        }

        return ranges
    }

    /// For hard-word selection: pick the next word after cursor.
    /// If cursor is inside a word, pick that word.
    private static func hardWordIndex(baseCursor: Int, ranges: [NSRange]) -> Int {
        guard !ranges.isEmpty else { return 0 }

        for (i, r) in ranges.enumerated() {
            if baseCursor <= r.location { return i }
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
}
