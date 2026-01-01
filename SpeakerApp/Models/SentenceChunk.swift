import Foundation

struct SentenceChunk: Identifiable, Codable, Hashable {
    /// Stable ID derived from timings (ms precision)
    let id: String
    let text: String
    let start: Double
    let end: Double

    init(text: String, start: Double, end: Double) {
        let s = Int((start * 1000.0).rounded())
        let e = Int((end * 1000.0).rounded())
        self.id = "\(s)_\(e)"
        self.text = text
        self.start = start
        self.end = end
    }
}
