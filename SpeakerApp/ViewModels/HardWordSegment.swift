import Foundation

/// One "hard word" marker extracted from the edited sentence text.
/// Stable identity is derived from the underlying word timing.
struct HardWordSegment: Identifiable, Codable, Hashable {
    /// stable: sentenceID|hw|startMs_endMs
    let id: String

    /// parent sentence id (SentenceChunk.id)
    let sentenceID: String

    /// display order inside the sentence
    let index: Int

    /// original word timing from Whisper (seconds)
    let baseStart: Double
    let baseEnd: Double

    /// extracted word (from WordTiming.word)
    var word: String

    init(sentenceID: String, index: Int, start: Double, end: Double, word: String) {
        self.sentenceID = sentenceID
        self.index = index
        self.baseStart = start
        self.baseEnd = end
        self.word = word
        self.id = Self.makeID(sentenceID: sentenceID, start: start, end: end)
    }

    static func makeID(sentenceID: String, start: Double, end: Double) -> String {
        let s = Int((start * 1000.0).rounded())
        let e = Int((end * 1000.0).rounded())
        return "\(sentenceID)|hw|\(s)_\(e)"
    }
}
