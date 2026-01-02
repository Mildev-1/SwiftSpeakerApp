import Foundation

enum SentenceSubchunkBuilder {
    static func subchunkID(sentenceID: String, start: Double, end: Double) -> String {
        let s = Int((start * 1000.0).rounded())
        let e = Int((end * 1000.0).rounded())
        return "\(sentenceID)|\(s)_\(e)"
    }

    /// Build sentence subchunks from sentence boundaries + saved manual cut times + edited text.
    /// Text is split by ⏸️ to match the number of pieces.
    static func build(sentence: SentenceChunk, editedText: String, manualCuts: [Double]) -> [SentenceSubchunk] {
        let cuts = manualCuts.sorted()

        var points: [Double] = [sentence.start]
        points.append(contentsOf: cuts)
        points.append(sentence.end)

        let parts = editedText
            .components(separatedBy: SentenceCursorTimeMapper.pauseEmoji)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        var out: [SentenceSubchunk] = []
        for i in 0..<(points.count - 1) {
            let s = points[i]
            let e = points[i + 1]
            let textPart = (i < parts.count) ? parts[i] : ""
            let id = subchunkID(sentenceID: sentence.id, start: s, end: e)
            out.append(SentenceSubchunk(id: id, sentenceID: sentence.id, index: i, baseStart: s, baseEnd: e, text: textPart))
        }
        return out
    }
}
