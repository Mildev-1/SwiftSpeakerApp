import Foundation

enum SentenceChunkBuilder {
    // Sentence ends
    private static let enders: Set<Character> = [".", "?", "!", "…"]

    // Punctuation that should NOT have a leading space
    private static let noSpaceBefore: Set<Character> = [".", ",", "?", "!", "…", ";", ":", ")", "]", "}", "\"", "”", "’"]

    static func build(from words: [WordTiming]) -> [SentenceChunk] {
        let sorted = words.sorted { $0.start < $1.start }
        guard !sorted.isEmpty else { return [] }

        var result: [SentenceChunk] = []
        var current: [WordTiming] = []

        func flush() {
            guard let first = current.first, let last = current.last else { return }
            let text = joinWords(current.map { $0.word })
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { current.removeAll(); return }

            result.append(SentenceChunk(text: text, start: first.start, end: last.end))
            current.removeAll()
        }

        for w in sorted {
            current.append(w)
            if let lastChar = w.word.last, enders.contains(lastChar) {
                flush()
            }
        }
        if !current.isEmpty { flush() }

        return result.filter { ($0.end - $0.start) > 0.03 }
    }

    private static func joinWords(_ tokens: [String]) -> String {
        var out = ""
        for t in tokens where !t.isEmpty {
            if out.isEmpty {
                out = t
                continue
            }
            if let first = t.first, noSpaceBefore.contains(first) {
                out += t
            } else {
                out += " " + t
            }
        }
        return out
    }
}
