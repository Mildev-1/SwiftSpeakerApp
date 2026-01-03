import Foundation
import SwiftUI

extension TranscriptViewModel {

    /// Practice UI sentence text:
    /// - keeps ⏸️ pauses visible (styled)
    /// - removes 🚀 markers (since they are editor-only markers)
    /// - highlights extracted hard-word segments (orange + bold), using the same saved extraction data
    func attributedDisplayText(for chunk: SentenceChunk) -> AttributedString {
        let raw = displayText(for: chunk)

        // Remove rockets only. Keep pauses.
        let display = raw.replacingOccurrences(of: SentenceCursorTimeMapper.rocketEmoji, with: "")

        var a = AttributedString(display)

        // Style pauses (⏸️) so they remain visible but not visually loud
        stylePauses(in: &a)

        // Highlight extracted hard-word segments (works for single word OR bundles if `word` contains multiple tokens)
        let segments = hardWordsBySentence[chunk.id] ?? []

        // Prefer longer phrases first to avoid partial matches stealing highlights
        let phrases: [String] = segments
            .map { $0.word.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { normalizeSpaces($0) }
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }

        var used: [Range<AttributedString.Index>] = []

        for phrase in phrases {
            // Find first match and highlight it (stable behavior, avoids highlighting duplicates unexpectedly)
            if let r = firstNonOverlappingRange(of: phrase, in: a, used: used) {
                a[r].foregroundColor = .orange
                a[r].font = .body.bold()
                used.append(r)
            }
        }

        return a
    }

    // MARK: - Helpers

    private func normalizeSpaces(_ s: String) -> String {
        let parts = s.split(whereSeparator: { $0.isWhitespace })
        return parts.joined(separator: " ")
    }

    private func stylePauses(in a: inout AttributedString) {
        let token = SentenceCursorTimeMapper.pauseEmoji
        var start = a.startIndex

        while start < a.endIndex, let r = a[start...].range(of: token) {
            a[r].foregroundColor = .secondary
            a[r].font = .caption
            start = r.upperBound
        }
    }

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

    private func rangesOverlap(_ a: Range<AttributedString.Index>, _ b: Range<AttributedString.Index>) -> Bool {
        a.lowerBound < b.upperBound && b.lowerBound < a.upperBound
    }
}
