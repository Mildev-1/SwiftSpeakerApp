import Foundation

/// Persisted transcript for one AudioItem (stored separately from the library list).
struct TranscriptRecord: Codable, Hashable {
    let text: String
    let words: [WordTiming]
    let languageCode: String?
    let model: String?
    let createdAt: Date

    init(
        text: String,
        words: [WordTiming],
        languageCode: String?,
        model: String?,
        createdAt: Date = Date()
    ) {
        self.text = text
        self.words = words
        self.languageCode = languageCode
        self.model = model
        self.createdAt = createdAt
    }
}
