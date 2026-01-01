import Foundation

struct WordTiming: Identifiable, Codable, Hashable {
    let id: UUID
    let word: String
    let start: Double   // seconds
    let end: Double     // seconds

    init(id: UUID = UUID(), word: String, start: Double, end: Double) {
        self.id = id
        self.word = word
        self.start = start
        self.end = end
    }
}
