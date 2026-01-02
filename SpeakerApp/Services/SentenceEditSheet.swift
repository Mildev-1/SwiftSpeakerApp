import SwiftUI

struct SentenceEditSheet: View {
    let itemID: UUID
    let chunk: SentenceChunk
    let audioURL: URL
    let words: [WordTiming]

    @ObservedObject var transcriptVM: TranscriptViewModel

    @Environment(\.dismiss) private var dismiss
    @StateObject private var playback = AudioPlaybackManager()

    // Draft editing (does NOT affect plan until Save)
    @State private var draftText: String
    @State private var selectedRange: NSRange = NSRange(location: 0, length: 0)
    @State private var isFocused: Bool = false
    @State private var isEditable: Bool = true
    @State private var resignToken: Int = 0

    // Bubble segments after Save (or loaded from persisted plan)
    @State private var subchunks: [SentenceSubchunk] = []

    // Per-bubble lock state (locked by default)
    @State private var unlocked: Set<String> = []

    init(itemID: UUID, chunk: SentenceChunk, audioURL: URL, words: [WordTiming], transcriptVM: TranscriptViewModel) {
        self.itemID = itemID
        self.chunk = chunk
        self.audioURL = audioURL
        self.words = words
        self.transcriptVM = transcriptVM
        _draftText = State(initialValue: transcriptVM.displayText(for: chunk))
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 14) {
                        // Sentence Play
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

                        // Draft editor (small)
                        let editorMax = geo.size.height * 0.35
                        CursorTextView(
                            text: $draftText,
                            selectedRange: $selectedRange,
                            isFocused: $isFocused,
                            isEditable: isEditable,
                            resignFocusToken: $resignToken
                        )
                        .frame(height: min(editorMax, 220)) // ~6 lines cap
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(.quaternary, lineWidth: 1)
                        )

                        // Save / Edit row
                        HStack(spacing: 12) {
                            Button {
                                savePauses()
                            } label: {
                                Label("Save", systemImage: "checkmark.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!isEditable)

                            Button {
                                // re-enable editing
                                isEditable = true
                            } label: {
                                Label("Edit", systemImage: "pencil")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(isEditable)
                        }

                        if !subchunks.isEmpty {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Sentence parts")
                                    .font(.headline)
                                    .padding(.top, 4)

                                ForEach(subchunks, id: \.id) { sc in
                                    partBubble(for: sc)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Text("No saved pauses in this sentence.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 6)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Sentence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isEditable && isFocused {
                        Button("Pause") { insertPauseEmoji() }
                    }
                }
            }
            .onAppear {
                playback.loadIfNeeded(url: audioURL)

                // Build initial bubbles from persisted plan (if already saved before)
                let savedText = transcriptVM.displayText(for: chunk)
                let savedCuts = (transcriptVM.manualCutsBySentence[chunk.id] ?? []).sorted()
                subchunks = SentenceSubchunkBuilder.build(sentence: chunk, editedText: savedText, manualCuts: savedCuts)

                // Draft starts from persisted text
                draftText = savedText
            }
        }
    }

    // MARK: Save

    private func savePauses() {
        // Commit draft → plan
        transcriptVM.syncManualCutsForSentence(itemID: itemID, chunk: chunk, finalEditedText: draftText)

        // Stop editing + resign focus
        isEditable = false
        resignToken += 1

        // Refresh bubbles from newly saved plan
        let cuts = (transcriptVM.manualCutsBySentence[chunk.id] ?? []).sorted()
        subchunks = SentenceSubchunkBuilder.build(sentence: chunk, editedText: draftText, manualCuts: cuts)

        // Ensure each new bubble has a fineTune entry (defaults 0,0)
        for sc in subchunks {
            if transcriptVM.fineTunesBySubchunk[sc.id] == nil {
                transcriptVM.fineTunesBySubchunk[sc.id] = SegmentFineTune()
            }
        }
        transcriptVM.saveCutPlan(itemID: itemID)
    }

    // MARK: Insert emoji

    private func insertPauseEmoji() {
        let pauseEmoji = SentenceCursorTimeMapper.pauseEmoji

        let ns = draftText as NSString
        let safeLoc = max(0, min(selectedRange.location, ns.length))
        let safeLen = max(0, min(selectedRange.length, ns.length - safeLoc))
        let r = NSRange(location: safeLoc, length: safeLen)

        draftText = ns.replacingCharacters(in: r, with: pauseEmoji)

        let newLoc = safeLoc + (pauseEmoji as NSString).length
        selectedRange = NSRange(location: newLoc, length: 0)
    }

    // MARK: Bubble UI

    @ViewBuilder
    private func partBubble(for sc: SentenceSubchunk) -> some View {
        let tune = transcriptVM.fineTune(for: sc.id)
        let isUnlocked = unlocked.contains(sc.id)

        VStack(alignment: .leading, spacing: 10) {
            // Play part
            Button {
                let adj = adjustedTimes(for: sc)
                playback.playSegmentOnce(url: audioURL, start: adj.start, end: adj.end, sentenceID: nil)
            } label: {
                Label("Play part \(sc.index + 1)", systemImage: "play.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)

            // Bubble text
            Text(sc.text.isEmpty ? "…" : sc.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.quaternary, lineWidth: 1)
                )

            // Sliders row with lock between
            HStack(spacing: 10) {
                Slider(
                    value: Binding(
                        get: { tune.startOffset },
                        set: { newVal in
                            guard isUnlocked else { return }
                            transcriptVM.setFineTune(itemID: itemID, subchunkID: sc.id, startOffset: newVal, endOffset: tune.endOffset)
                        }
                    ),
                    in: -0.5...0.5,
                    step: 0.01
                )
                .disabled(!isUnlocked)

                Button {
                    if isUnlocked { unlocked.remove(sc.id) } else { unlocked.insert(sc.id) }
                } label: {
                    Image(systemName: isUnlocked ? "lock.open.fill" : "lock.fill")
                        .font(.headline)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)

                Slider(
                    value: Binding(
                        get: { tune.endOffset },
                        set: { newVal in
                            guard isUnlocked else { return }
                            transcriptVM.setFineTune(itemID: itemID, subchunkID: sc.id, startOffset: tune.startOffset, endOffset: newVal)
                        }
                    ),
                    in: -0.5...0.5,
                    step: 0.01
                )
                .disabled(!isUnlocked)
            }
            .opacity(isUnlocked ? 1.0 : 0.65)

            // tiny hint
            Text("Fine tune: start \(fmt(tune.startOffset))s, end \(fmt(tune.endOffset))s")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    private func adjustedTimes(for sc: SentenceSubchunk) -> (start: Double, end: Double) {
        let tune = transcriptVM.fineTune(for: sc.id)
        var s = sc.baseStart + tune.startOffset
        var e = sc.baseEnd + tune.endOffset

        // keep inside sentence and valid
        s = max(chunk.start, min(s, chunk.end))
        e = max(chunk.start, min(e, chunk.end))
        if e <= s { e = min(chunk.end, s + 0.05) }
        return (s, e)
    }

    private func fmt(_ v: Double) -> String {
        String(format: "%.2f", v)
    }
}
