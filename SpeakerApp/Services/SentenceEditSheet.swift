import SwiftUI

struct SentenceEditSheet: View {
    let itemID: UUID
    let chunk: SentenceChunk
    let audioURL: URL
    let words: [WordTiming]

    @ObservedObject var transcriptVM: TranscriptViewModel

    @Environment(\.dismiss) private var dismiss
    @StateObject private var playback = AudioPlaybackManager()

    @State private var draftText: String
    @State private var selectedRange: NSRange = NSRange(location: 0, length: 0)
    @State private var isFocused: Bool = false
    @State private var isEditable: Bool = true
    @State private var resignToken: Int = 0

    @State private var editorHeight: CGFloat = 80

    @State private var subchunks: [SentenceSubchunk] = []
    @State private var unlocked: Set<String> = []

    // ✅ NEW: hard words list + locks
    @State private var hardWords: [HardWordSegment] = []
    @State private var unlockedHardWords: Set<String> = []

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

                        // MAIN CARD: Play/Stop + editor + Save/Edit
                        VStack(spacing: 12) {

                            // Play + Stop row
                            HStack(spacing: 12) {
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

                                Button {
                                    playback.stop()
                                } label: {
                                    Label("Stop", systemImage: "stop.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .disabled(!playback.isPlaying && !playback.isPartialPlaying)
                            }

                            // helper label above editor
                            Text("Tap to edit manual pauses / hard words")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            let editorMax = geo.size.height * 0.35
                            AutoSizingStyledCursorTextView(
                                text: $draftText,
                                selectedRange: $selectedRange,
                                isFocused: $isFocused,
                                isEditable: isEditable,
                                resignFocusToken: $resignToken,
                                measuredHeight: $editorHeight
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: min(max(editorHeight, 60), min(editorMax, 260)))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.black.opacity(0.18), lineWidth: 1)
                            )

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
                                    isEditable = true
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .disabled(isEditable)
                            }
                        }
                        .padding(12)
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(.quaternary, lineWidth: 1)
                        )

                        // Sentence parts
                        if !subchunks.isEmpty {
                            VStack(spacing: 10) {
                                Text("Sentence parts")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity, alignment: .center)

                                ForEach(subchunks, id: \.id) { sc in
                                    partCard(for: sc)
                                }
                            }
                            .padding(.top, 6)
                        }

                        // ✅ NEW: Hard words list
                        VStack(spacing: 10) {
                            Text("Hard words")
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .center)

                            if hardWords.isEmpty {
                                Text("Tap 🚀 in the toolbar to mark a hard word (the next word after 🚀).")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 12)
                            } else {
                                ForEach(hardWords, id: \.id) { hw in
                                    hardWordCard(for: hw)
                                }
                            }
                        }
                        .padding(.top, 6)
                    }
                    .padding()
                }
                .onAppear {
                    playback.loadIfNeeded(url: audioURL)

                    let savedText = transcriptVM.displayText(for: chunk)
                    let savedCuts = (transcriptVM.manualCutsBySentence[chunk.id] ?? []).sorted()
                    subchunks = SentenceSubchunkBuilder.build(sentence: chunk, editedText: savedText, manualCuts: savedCuts)

                    // Prefer persisted hard words; if none, compute from current text (no persistence until Save)
                    if let persisted = transcriptVM.hardWordsBySentence[chunk.id] {
                        hardWords = persisted
                    } else {
                        hardWords = SentenceCursorTimeMapper.hardWordSegmentsFromEditedText(
                            editedText: savedText,
                            chunk: chunk,
                            allWords: transcriptVM.words
                        )
                    }

                    draftText = savedText
                }
                .onDisappear {
                    playback.stop()
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") {
                            playback.stop()
                            dismiss()
                        }
                    }

                    ToolbarItemGroup(placement: .topBarTrailing) {
                        if isEditable && isFocused {
                            Button {
                                insertPauseEmoji()
                            } label: {
                                Label("Pause", systemImage: "pause.circle")
                            }

                            Button {
                                insertRocketEmoji()
                            } label: {
                                Text("🚀")
                                    .font(.headline)
                                    .padding(.horizontal, 6)
                            }
                            .accessibilityLabel("Add hard word marker")
                        }
                    }
                }
            }
        }
    }

    private func savePauses() {
        transcriptVM.syncManualCutsForSentence(itemID: itemID, chunk: chunk, finalEditedText: draftText)

        isEditable = false
        resignToken += 1

        let cuts = (transcriptVM.manualCutsBySentence[chunk.id] ?? []).sorted()
        subchunks = SentenceSubchunkBuilder.build(sentence: chunk, editedText: draftText, manualCuts: cuts)

        for sc in subchunks {
            if transcriptVM.fineTunesBySubchunk[sc.id] == nil {
                transcriptVM.fineTunesBySubchunk[sc.id] = SegmentFineTune()
            }
        }

        // refresh from persisted state
        hardWords = transcriptVM.hardWordsBySentence[chunk.id] ?? []

        for hw in hardWords {
            if transcriptVM.fineTunesByHardWord[hw.id] == nil {
                transcriptVM.fineTunesByHardWord[hw.id] = SegmentFineTune()
            }
        }

        transcriptVM.saveCutPlan(itemID: itemID)
    }

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

    private func insertRocketEmoji() {
        let rocket = SentenceCursorTimeMapper.rocketEmoji

        let ns = draftText as NSString
        let safeLoc = max(0, min(selectedRange.location, ns.length))
        let safeLen = max(0, min(selectedRange.length, ns.length - safeLoc))
        let r = NSRange(location: safeLoc, length: safeLen)

        draftText = ns.replacingCharacters(in: r, with: rocket)

        let newLoc = safeLoc + (rocket as NSString).length
        selectedRange = NSRange(location: newLoc, length: 0)
    }

    // Each part has its own rounded rectangle wrapper
    @ViewBuilder
    private func partCard(for sc: SentenceSubchunk) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            partBubble(for: sc)
        }
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        )
        .frame(maxWidth: 560, alignment: .center)
    }

    @ViewBuilder
    private func partBubble(for sc: SentenceSubchunk) -> some View {
        let tune = transcriptVM.fineTune(for: sc.id)
        let isUnlocked = unlocked.contains(sc.id)

        VStack(alignment: .leading, spacing: 10) {
            Button {
                let adj = adjustedTimes(for: sc)
                playback.playSegmentOnce(url: audioURL, start: adj.start, end: adj.end, sentenceID: nil)
            } label: {
                Label("Play part \(sc.index + 1)", systemImage: "play.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)

            Text(sc.text.isEmpty ? "…" : sc.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(.systemGray3), lineWidth: 1)
                )

            HStack(spacing: 10) {
                Slider(
                    value: Binding(
                        get: { tune.startOffset },
                        set: { newVal in
                            guard isUnlocked else { return }
                            transcriptVM.setFineTune(
                                itemID: itemID,
                                subchunkID: sc.id,
                                startOffset: newVal,
                                endOffset: tune.endOffset
                            )
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
                            transcriptVM.setFineTune(
                                itemID: itemID,
                                subchunkID: sc.id,
                                startOffset: tune.startOffset,
                                endOffset: newVal
                            )
                        }
                    ),
                    in: -0.5...0.5,
                    step: 0.01
                )
                .disabled(!isUnlocked)
            }
            .opacity(isUnlocked ? 1.0 : 0.65)

            Text("Fine tune: start \(fmt(tune.startOffset))s, end \(fmt(tune.endOffset))s")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // ✅ NEW: hard word card
    @ViewBuilder
    private func hardWordCard(for hw: HardWordSegment) -> some View {
        let tune = transcriptVM.fineTuneForHardWord(hw.id)
        let isUnlocked = unlockedHardWords.contains(hw.id)

        VStack(alignment: .leading, spacing: 10) {
            Button {
                let adj = adjustedTimes(forHardWord: hw)
                playback.playSegmentOnce(url: audioURL, start: adj.start, end: adj.end, sentenceID: nil)
            } label: {
                Label("Play word", systemImage: "play.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)

            // Display word in a TextField-style control (read-only for now)
            TextField("", text: .constant(hw.word))
                .textFieldStyle(.roundedBorder)
                .disabled(true)

            HStack(spacing: 10) {
                Slider(
                    value: Binding(
                        get: { tune.startOffset },
                        set: { newVal in
                            guard isUnlocked else { return }
                            transcriptVM.setHardWordFineTune(
                                itemID: itemID,
                                hardWordID: hw.id,
                                startOffset: newVal,
                                endOffset: tune.endOffset
                            )
                        }
                    ),
                    in: -0.5...0.5,
                    step: 0.01
                )
                .disabled(!isUnlocked)

                Button {
                    if isUnlocked { unlockedHardWords.remove(hw.id) } else { unlockedHardWords.insert(hw.id) }
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
                            transcriptVM.setHardWordFineTune(
                                itemID: itemID,
                                hardWordID: hw.id,
                                startOffset: tune.startOffset,
                                endOffset: newVal
                            )
                        }
                    ),
                    in: -0.5...0.5,
                    step: 0.01
                )
                .disabled(!isUnlocked)
            }
            .opacity(isUnlocked ? 1.0 : 0.65)

            Text("Fine tune: start \(fmt(tune.startOffset))s, end \(fmt(tune.endOffset))s")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        )
        .frame(maxWidth: 560, alignment: .center)
    }

    private func adjustedTimes(for sc: SentenceSubchunk) -> (start: Double, end: Double) {
        let tune = transcriptVM.fineTune(for: sc.id)
        var s = sc.baseStart + tune.startOffset
        var e = sc.baseEnd + tune.endOffset

        s = max(chunk.start, min(s, chunk.end))
        e = max(chunk.start, min(e, chunk.end))
        if e <= s { e = min(chunk.end, s + 0.05) }
        return (s, e)
    }

    private func adjustedTimes(forHardWord hw: HardWordSegment) -> (start: Double, end: Double) {
        let tune = transcriptVM.fineTuneForHardWord(hw.id)
        var s = hw.baseStart + tune.startOffset
        var e = hw.baseEnd + tune.endOffset

        s = max(chunk.start, min(s, chunk.end))
        e = max(chunk.start, min(e, chunk.end))
        if e <= s { e = min(chunk.end, s + 0.05) }
        return (s, e)
    }

    private func fmt(_ v: Double) -> String {
        String(format: "%.2f", v)
    }
}
