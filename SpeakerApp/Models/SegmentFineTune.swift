import Foundation

/// Fine-tuning offsets for one sub-segment inside a sentence.
/// Offsets are always clamped to [-0.5, +0.5] seconds.
struct SegmentFineTune: Codable, Hashable {
    var startOffset: Double  // seconds
    var endOffset: Double    // seconds

    init(startOffset: Double = 0, endOffset: Double = 0) {
        self.startOffset = startOffset
        self.endOffset = endOffset
    }
}
