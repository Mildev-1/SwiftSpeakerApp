import SwiftUI

struct SentenceEditSheet: View {
    let chunk: SentenceChunk
    let audioURL: URL
    let words: [WordTiming]

    /// Current editable text for this sentence (stored per chunk.id)
    @Binding var editedText: String

    /// Called when user inserts a pause mark; provides mapped absolute time
    let onAddPauseTime: (Double) -> Void

    /// Called when closing to persist text edits
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var playback = AudioPlaybackManager()

    @State private var selectedRange: NSRange = NSRange(location: 0, length: 0)
    @State private var isFocused: Bool = false

    private let pauseEmoji = SentenceCursorTimeMapper.pauseEmoji

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                // Play button
                Button {
                    playback.playSegmentOnce(
                        url: audioURL,
                        start: chunk.start,
                        end: chunk.end,
                        sentenceID: chunk.id
                    )
                } label: {
                    Label(playback.isPlaying ? "Playing…" : "Play sentence", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!FileManager.default.fileExists(atPath: audioURL.path))

                // Editable text with cursor tracking
                CursorTextView(text: $editedText, selectedRange: $selectedRange, isFocused: $isFocused)
                    .frame(minHeight: 220)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(.quaternary, lineWidth: 1)
                    )
            }
            .padding(16)
            .navigationTitle("Sentence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        onSave()
                        dismiss()
                    }
                }

                // Show Pause button only when cursor is active in the text view
                ToolbarItem(placement: .topBarTrailing) {
                    if isFocused {
                        Button("Pause") {
                            insertPauseEmojiAndPersistTime()
                        }
                    }
                }
            }
            .onAppear {
                playback.loadIfNeeded(url: audioURL)
            }
        }
    }

    private func insertPauseEmojiAndPersistTime() {
        // Insert emoji at cursor selection range
        let ns = editedText as NSString
        let safeLoc = max(0, min(selectedRange.location, ns.length))
        let safeLen = max(0, min(selectedRange.length, ns.length - safeLoc))
        let r = NSRange(location: safeLoc, length: safeLen)

        let newText = ns.replacingCharacters(in: r, with: pauseEmoji)
        editedText = newText

        // Move cursor after inserted emoji
        let newLoc = safeLoc + (pauseEmoji as NSString).length
        selectedRange = NSRange(location: newLoc, length: 0)

        // Map to time and persist cut time
        if let t = SentenceCursorTimeMapper.cursorTime(
            editedText: editedText,
            cursorLocationUTF16: newLoc,
            chunk: chunk,
            allWords: words
        ) {
            onAddPauseTime(t)
        }
    }
}
