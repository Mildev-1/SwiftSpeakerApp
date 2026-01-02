import Foundation

struct SentenceSubchunk: Identifiable, Hashable {
    let id: String                 // stable: sentenceID|startMs_endMs
    let sentenceID: String
    let index: Int
    let baseStart: Double          // seconds (before fine-tune offsets)
    let baseEnd: Double            // seconds (before fine-tune offsets)
    let text: String               // part text (split by ⏸️)
}
