import Foundation
import SwiftUI

extension TranscriptViewModel {

    /// Practice + Fullscreen sentence text:
    /// - keeps ⏸️ pauses visible (styled)
    /// - removes 🚀 markers (editor-only markers)
    /// - highlights extracted hard-word segments (orange + bold), using saved extraction data
    /// - robust fallback: if exact phrase not found, fuzzy-match by tokens (handles small typos / spacing)
    func attributedDisplayText(for chunk: SentenceChunk) -> AttributedString {
        let raw = displayText(for: chunk)

        // Remove rockets only. Keep pauses.
        let display = raw.replacingOccurrences(of: SentenceCursorTimeMapper.rocketEmoji, with: "")

        var a = AttributedString(display)

        // Style pauses (⏸️) so they remain visible but not visually loud
        stylePauses(in: &a)

        // Highlight extracted hard-word segments (single word OR bundles)
        let segments = hardWordsBySentence[chunk.id] ?? []

        // Prefer longer phrases first to avoid partial matches stealing highlights
        let phrases: [String] = segments
            .map { $0.word.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { normalizeSpaces($0) }
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }

        var used: [Range<AttributedString.Index>] = []

        for phrase in phrases {
            // 1) Exact match
            if let r = firstNonOverlappingRange(of: phrase, in: a, used: used) {
                applyHighlight(to: r, in: &a)
                used.append(r)
                continue
            }

            // 2) Fuzzy fallback (token window match)
            if let r = firstNonOverlappingFuzzyRange(of: phrase, in: a, used: used) {
                applyHighlight(to: r, in: &a)
                used.append(r)
                continue
            }
        }

        return a
    }

    // MARK: - Styling

    private func applyHighlight(to r: Range<AttributedString.Index>, in a: inout AttributedString) {
        a[r].foregroundColor = .orange
        // Bold without forcing fixed font size (respects fullscreen scaling)
        a[r].inlinePresentationIntent = .stronglyEmphasized
    }

    private func stylePauses(in a: inout AttributedString) {
        let token = SentenceCursorTimeMapper.pauseEmoji
        var start = a.startIndex

        while start < a.endIndex, let r = a[start...].range(of: token) {
            a[r].foregroundColor = .secondary
            a[r].inlinePresentationIntent = .emphasized
            start = r.upperBound
        }
    }

    // MARK: - Exact matching helpers

    private func firstNonOverlappingRange(
        of phrase: String,
        in a: AttributedString,
        used: [Range<AttributedString.Index>]
    ) -> Range<AttributedString.Index>? {
        var searchStart = a.startIndex
        while searchStart < a.endIndex, let r = a[searchStart...].range(of: phrase) {
            if !used.contains(where: { rangesOverlap($0, r) }) {
                return r
            }
            searchStart = r.upperBound
        }
        return nil
    }

    // MARK: - Fuzzy matching (token window)

    private func firstNonOverlappingFuzzyRange(
        of phrase: String,
        in a: AttributedString,
        used: [Range<AttributedString.Index>]
    ) -> Range<AttributedString.Index>? {
        let base = String(a.characters)

        let phraseTokens = tokenizeForMatch(phrase).map { $0.token }
        guard phraseTokens.count >= 2 else { return nil } // fuzzy only useful for multi-token phrases

        let baseTokens = tokenizeForMatch(base)
        guard baseTokens.count >= phraseTokens.count else { return nil }

        let window = phraseTokens.count

        // Require at least 75% token matches (allows 1 mismatch for 4-word phrase, etc.)
        let needed = Int(ceil(Double(window) * 0.75))

        for i in 0...(baseTokens.count - window) {
            var matches = 0

            for j in 0..<window {
                if baseTokens[i + j].token == phraseTokens[j] {
                    matches += 1
                }
            }

            if matches >= needed {
                // Range from first token start to last token end
                let lo = baseTokens[i].range.lowerBound
                let hi = baseTokens[i + window - 1].range.upperBound
                let stringRange = lo..<hi

                // Convert String range -> AttributedString range
                if let ar = attributedRange(from: stringRange, in: a),
                   !used.contains(where: { rangesOverlap($0, ar) }) {
                    return ar
                }
            }
        }

        return nil
    }

    private struct TokenRange {
        let token: String
        let range: Range<String.Index>
    }

    private func tokenizeForMatch(_ s: String) -> [TokenRange] {
        // Tokenize by "non-whitespace runs", then normalize each token by stripping punctuation-ish edges.
        // This keeps indices stable so we can build a highlight range.
        var out: [TokenRange] = []
        out.reserveCapacity(24)

        var i = s.startIndex
        while i < s.endIndex {
            // skip whitespace
            while i < s.endIndex, s[i].isWhitespace { i = s.index(after: i) }
            if i >= s.endIndex { break }

            let start = i
            while i < s.endIndex, !s[i].isWhitespace { i = s.index(after: i) }
            let end = i

            let rawToken = String(s[start..<end])
            let norm = normalizeToken(rawToken)
            if !norm.isEmpty {
                out.append(.init(token: norm, range: start..<end))
            }
        }

        return out
    }

    private func normalizeToken(_ t: String) -> String {
        // Lowercase and trim common punctuation around tokens
        let lowered = t.lowercased()
        let trimmed = lowered.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.symbols))
        return trimmed
    }

    private func attributedRange(from stringRange: Range<String.Index>, in a: AttributedString) -> Range<AttributedString.Index>? {
        let base = String(a.characters)
        // Ensure the stringRange is valid for the current base
        guard stringRange.lowerBound >= base.startIndex, stringRange.upperBound <= base.endIndex else {
            return nil
        }
        guard
            let lo = AttributedString.Index(stringRange.lowerBound, within: a),
            let hi = AttributedString.Index(stringRange.upperBound, within: a)
        else { return nil }
        return lo..<hi
    }

    // MARK: - Shared helpers

    private func normalizeSpaces(_ s: String) -> String {
        let parts = s.split(whereSeparator: { $0.isWhitespace })
        return parts.joined(separator: " ")
    }

    private func rangesOverlap(_ a: Range<AttributedString.Index>, _ b: Range<AttributedString.Index>) -> Bool {
        a.lowerBound < b.upperBound && b.lowerBound < a.upperBound
    }
}
