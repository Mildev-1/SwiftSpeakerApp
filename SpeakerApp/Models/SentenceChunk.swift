import Foundation

struct SentenceChunk: Identifiable, Codable, Hashable {
    let id: UUID
    let text: String
    let start: Double
    let end: Double

    init(id: UUID = UUID(), text: String, start: Double, end: Double) {
        self.id = id
        self.text = text
        self.start = start
        self.end = end
    }
}
