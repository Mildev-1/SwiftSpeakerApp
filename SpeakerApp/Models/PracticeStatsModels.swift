import Foundation

enum PracticeMode: String, Codable {
    case words
    case sentences
    case mixed
    case partial
}

struct PracticeSessionLog: Codable, Identifiable, Hashable {
    let id: UUID

    let itemID: UUID
    let itemTitle: String

    let startedAt: Date
    let durationSeconds: Double

    let mode: PracticeMode
    let flaggedOnly: Bool

    let wordRepeats: Int
    let sentenceRepeats: Int
}
