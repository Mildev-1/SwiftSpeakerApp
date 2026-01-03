import SwiftUI

struct PracticeView: View {
    let item: AudioItem
    let onClose: () -> Void

    @EnvironmentObject private var library: AudioLibrary

    @StateObject private var transcriptVM = TranscriptViewModel()
    @StateObject private var playback = AudioPlaybackManager()

    @State private var showPlaybackScreen: Bool = false

    // UI state (mirrors PlaybackSettings, persisted in TranscriptCutPlan)
    @State private var playbackFontScale: Double = 1.0

    // Sentence shadowing
    @State private var sentenceShadowingOn: Bool = false
    @State private var sentenceRepeats: Int = 2
    @State private var sentenceSilenceMultiplier: Double = 1.0
    @State private var sentencesPauseOnly: Bool = false
    @State private var flaggedOnly: Bool = false

    // Words shadowing
    @State private var wordsShadowingOn: Bool = false
    @State private var wordRepeats: Int = 2
    @State private var wordSilenceMultiplier: Double = 1.0

    private var storedMP3URL: URL {
        AudioStorage.shared.urlForStoredFile(relativePath: item.storedRelativePath)
    }

    private var hasTranscript: Bool {
        !transcriptVM.sentenceChunks.isEmpty
    }

    private var filteredSentenceChunksForPartial: [SentenceChunk] {
        if flaggedOnly {
            return transcriptVM.sentenceChunks.filter { transcriptVM.flaggedSentenceIDs.contains($0.id) }
        }
        return transcriptVM.sentenceChunks
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                topBar

                ScrollView {
                    VStack(spacing: 18) {
                        titleSection
                        generalPlayCard
                        playbackFontCard
                        sentenceShadowingCard
                        wordsShadowingCard
                        partialPlayCard
                        sentencesSection
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 16)
                }
            }
        }
        .onAppear {
            transcriptVM.loadIfAvailable(itemID: item.id)
            applySavedPlaybackSettings()
        }

        // Persist settings changes
        .onChange(of: playbackFontScale) { _ in persistPlaybackSettings() }

        // ✅ Mixed mode requires NOT forcing mutual exclusion
        .onChange(of: sentenceShadowingOn) { _ in persistPlaybackSettings() }
        .onChange(of: wordsShadowingOn) { _ in persistPlaybackSettings() }

        .onChange(of: sentenceRepeats) { _ in persistPlaybackSettings() }
        .onChange(of: sentenceSilenceMultiplier) { _ in persistPlaybackSettings() }
        .onChange(of: sentencesPauseOnly) { _ in persistPlaybackSettings() }
        .onChange(of: flaggedOnly) { _ in persistPlaybackSettings() }
        .onChange(of: wordRepeats) { _ in persistPlaybackSettings() }
        .onChange(of: wordSilenceMultiplier) { _ in persistPlaybackSettings() }

        .fullScreenCover(isPresented: $showPlaybackScreen) {
            PlaybackScreenView(
                item: item,
                playback: playback,
                transcriptVM: transcriptVM,
                isPresented: $showPlaybackScreen
            )
        }
    }

    // MARK: - UI building blocks

    private var background: some View {
        Color(.systemBackground).ignoresSafeArea()
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                playback.stop()
                onClose()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var titleSection: some View {
        HStack {
            Text(item.scriptName.isEmpty ? "Practice" : item.scriptName)
                .font(.title3)
                .fontWeight(.semibold)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 12)
        }
    }

    private var generalPlayCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                Text("General")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    showPlaybackScreen = true
                } label: {
                    Label("Open Fullscreen", systemImage: "rectangle.inset.filled.and.person.filled")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var playbackFontCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Playback font size")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Image(systemName: "textformat.size.smaller")
                        .foregroundStyle(.secondary)
                    Slider(value: $playbackFontScale, in: 0.8...1.6, step: 0.05)
                    Image(systemName: "textformat.size.larger")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var sentenceShadowingCard: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Sentence Shadowing")
                        .font(.headline)
                    Spacer()
                    Toggle("", isOn: $sentenceShadowingOn)
                        .labelsHidden()
                }

                if sentenceShadowingOn {
                    VStack(alignment: .leading, spacing: 12) {
                        repeatsSelector(
                            title: "Repetitions",
                            selection: $sentenceRepeats,
                            options: [1, 2, 3]
                        )

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Silence multiplier")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Slider(value: $sentenceSilenceMultiplier, in: 0.5...2.0, step: 0.1)
                            Text("\(Int(sentenceSilenceMultiplier * 100))%")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Toggle("Sentences pause only", isOn: $sentencesPauseOnly)
                            .font(.subheadline)
                    }
                }
            }
        }
    }

    private var wordsShadowingCard: some View {
        let wordSegs = buildWordSegments(flaggedOnly: flaggedOnly)

        return card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Words Shadowing")
                        .font(.headline)

                    Spacer()

                    Toggle("", isOn: $wordsShadowingOn)
                        .labelsHidden()
                        .disabled(wordSegs.isEmpty)
                }

                if wordSegs.isEmpty {
                    Text("No hard words marked (🚀) in Edit yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if wordsShadowingOn {
                    VStack(alignment: .leading, spacing: 12) {
                        repeatsSelector(
                            title: "Repetitions",
                            selection: $wordRepeats,
                            options: [1, 2, 3, 4, 5]
                        )

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Silence multiplier")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Slider(value: $wordSilenceMultiplier, in: 0.5...15.0, step: 0.1)
                            Text("\(Int(wordSilenceMultiplier * 100))%")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var partialPlayCard: some View {
        return card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Partial play")
                    .font(.headline)

                Toggle("Flagged Only", isOn: $flaggedOnly)
                    .font(.subheadline)

                HStack(spacing: 12) {
                    Button {
                        guard FileManager.default.fileExists(atPath: storedMP3URL.path) else { return }
                        guard hasTranscript else { return }

                        let chunksToPlay = filteredSentenceChunksForPartial
                        guard !chunksToPlay.isEmpty else { return }

                        let settings = PlaybackSettings(
                            repeatPracticeEnabled: sentenceShadowingOn,
                            practiceRepeats: sentenceRepeats,
                            practiceSilenceMultiplier: sentenceSilenceMultiplier,
                            sentencesPauseOnly: sentencesPauseOnly,
                            playbackFontScale: playbackFontScale,
                            flaggedOnly: flaggedOnly,
                            wordShadowingEnabled: wordsShadowingOn,
                            wordPracticeRepeats: wordRepeats,
                            wordPracticeSilenceMultiplier: wordSilenceMultiplier
                        ).clamped()

                        transcriptVM.setPlaybackSettings(itemID: item.id, settings)

                        // ✅ Mixed mode when BOTH toggles are ON
                        if sentenceShadowingOn && wordsShadowingOn {
                            let wordSegsBySentence = buildWordSegmentsBySentence(flaggedOnly: flaggedOnly)

                            playback.togglePartialPlayMixed(
                                url: storedMP3URL,
                                chunks: chunksToPlay,
                                manualCutsBySentence: transcriptVM.manualCutsBySentence,
                                fineTunesBySubchunk: transcriptVM.fineTunesBySubchunk,
                                mode: settings.repeatPracticeEnabled
                                    ? .repeatPractice(
                                        repeats: settings.practiceRepeats,
                                        silenceMultiplier: settings.practiceSilenceMultiplier,
                                        sentencesPauseOnly: settings.sentencesPauseOnly
                                    )
                                    : .beepBetweenCuts,
                                wordSegmentsBySentence: wordSegsBySentence,
                                wordRepeats: settings.wordPracticeRepeats,
                                wordSilenceMultiplier: settings.wordPracticeSilenceMultiplier
                            )

                            showPlaybackScreen = true
                            return
                        }

                        // Words-only
                        if wordsShadowingOn {
                            let segs = buildWordSegments(flaggedOnly: flaggedOnly)
                            if segs.isEmpty { return }

                            playback.togglePartialPlayWordSegments(
                                url: storedMP3URL,
                                segments: segs,
                                repeats: settings.wordPracticeRepeats,
                                silenceMultiplier: settings.wordPracticeSilenceMultiplier
                            )

                            showPlaybackScreen = true
                            return
                        }

                        // Sentence-only
                        playback.togglePartialPlay(
                            url: storedMP3URL,
                            chunks: chunksToPlay,
                            manualCutsBySentence: transcriptVM.manualCutsBySentence,
                            fineTunesBySubchunk: transcriptVM.fineTunesBySubchunk,
                            mode: settings.repeatPracticeEnabled
                                ? .repeatPractice(
                                    repeats: settings.practiceRepeats,
                                    silenceMultiplier: settings.practiceSilenceMultiplier,
                                    sentencesPauseOnly: settings.sentencesPauseOnly
                                )
                                : .beepBetweenCuts
                        )

                        showPlaybackScreen = true
                    } label: {
                        Label("Partial Play", systemImage: playback.isPartialPlaying ? "stop.fill" : "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!FileManager.default.fileExists(atPath: storedMP3URL.path) || !hasTranscript)

                    Button {
                        // bump repeats quickly
                        if sentenceShadowingOn && !wordsShadowingOn {
                            sentenceRepeats = min(3, sentenceRepeats + 1)
                        } else if wordsShadowingOn && !sentenceShadowingOn {
                            wordRepeats = min(5, wordRepeats + 1)
                        } else if sentenceShadowingOn && wordsShadowingOn {
                            // mixed: bump sentence reps (keeps UI simple)
                            sentenceRepeats = min(3, sentenceRepeats + 1)
                        }
                    } label: {
                        Label("Repeat +", systemImage: "repeat")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var sentencesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if transcriptVM.sentenceChunks.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Sentences")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(transcriptVM.sentenceChunks.enumerated()), id: \.element.id) { idx, chunk in
                            PracticeSentenceFlagRow(
                                chunk: chunk,
                                index: idx + 1,
                                itemID: item.id,
                                transcriptVM: transcriptVM
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
    }

    private func repeatsSelector(
        title: String,
        selection: Binding<Int>,
        options: [Int]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                ForEach(options, id: \.self) { v in
                    Button {
                        selection.wrappedValue = v
                    } label: {
                        Text("\(v)x")
                            .font(.subheadline)
                            .fontWeight(selection.wrappedValue == v ? .semibold : .regular)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(selection.wrappedValue == v ? Color(.systemBlue).opacity(0.18) : Color(.tertiarySystemFill))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func applySavedPlaybackSettings() {
        let s = transcriptVM.playbackSettings.clamped()
        playbackFontScale = s.playbackFontScale

        // sentence
        sentenceShadowingOn = s.repeatPracticeEnabled
        sentenceRepeats = s.practiceRepeats
        sentenceSilenceMultiplier = s.practiceSilenceMultiplier
        sentencesPauseOnly = s.sentencesPauseOnly
        flaggedOnly = s.flaggedOnly

        // words
        wordsShadowingOn = s.wordShadowingEnabled
        wordRepeats = s.wordPracticeRepeats
        wordSilenceMultiplier = s.wordPracticeSilenceMultiplier
    }

    private func persistPlaybackSettings() {
        let s = PlaybackSettings(
            repeatPracticeEnabled: sentenceShadowingOn,
            practiceRepeats: sentenceRepeats,
            practiceSilenceMultiplier: sentenceSilenceMultiplier,
            sentencesPauseOnly: sentencesPauseOnly,
            playbackFontScale: playbackFontScale,
            flaggedOnly: flaggedOnly,
            wordShadowingEnabled: wordsShadowingOn,
            wordPracticeRepeats: wordRepeats,
            wordPracticeSilenceMultiplier: wordSilenceMultiplier
        ).clamped()

        transcriptVM.setPlaybackSettings(itemID: item.id, s)
        transcriptVM.saveCutPlan(itemID: item.id)
    }

    // MARK: - Word segment extraction (flat list)

    private func buildWordSegments(flaggedOnly: Bool) -> [AudioPlaybackManager.TimedSegment] {
        let boundsBySentence: [String: (Double, Double)] = Dictionary(
            uniqueKeysWithValues: transcriptVM.sentenceChunks.map { ($0.id, ($0.start, $0.end)) }
        )

        var out: [AudioPlaybackManager.TimedSegment] = []
        out.reserveCapacity(32)

        for (sentenceID, words) in transcriptVM.hardWordsBySentence {
            if flaggedOnly && !transcriptVM.flaggedSentenceIDs.contains(sentenceID) { continue }
            guard let bounds = boundsBySentence[sentenceID] else { continue }

            for hw in words {
                let tune = transcriptVM.fineTunesByHardWord[hw.id] ?? SegmentFineTune()

                var s = hw.baseStart + tune.startOffset
                var e = hw.baseEnd + tune.endOffset

                s = max(bounds.0, min(s, bounds.1))
                e = max(bounds.0, min(e, bounds.1))
                if e <= s { e = min(bounds.1, s + 0.05) }

                if (e - s) < 0.02 { continue }

                out.append(.init(sentenceID: sentenceID, start: s, end: e))
            }
        }

        return out.sorted { $0.start < $1.start }
    }

    // MARK: - Word segment extraction (grouped by sentence) ✅ FIXED SCOPE

    private func buildWordSegmentsBySentence(flaggedOnly: Bool) -> [String: [AudioPlaybackManager.TimedSegment]] {
        let boundsBySentence: [String: (Double, Double)] = Dictionary(
            uniqueKeysWithValues: transcriptVM.sentenceChunks.map { ($0.id, ($0.start, $0.end)) }
        )

        var out: [String: [AudioPlaybackManager.TimedSegment]] = [:]
        out.reserveCapacity(32)

        for (sentenceID, words) in transcriptVM.hardWordsBySentence {
            if flaggedOnly && !transcriptVM.flaggedSentenceIDs.contains(sentenceID) { continue }
            guard let bounds = boundsBySentence[sentenceID] else { continue }

            var segs: [AudioPlaybackManager.TimedSegment] = []
            segs.reserveCapacity(words.count)

            for hw in words {
                let tune = transcriptVM.fineTunesByHardWord[hw.id] ?? SegmentFineTune()

                var s = hw.baseStart + tune.startOffset
                var e = hw.baseEnd + tune.endOffset

                s = max(bounds.0, min(s, bounds.1))
                e = max(bounds.0, min(e, bounds.1))
                if e <= s { e = min(bounds.1, s + 0.05) }

                if (e - s) < 0.02 { continue }

                segs.append(.init(sentenceID: sentenceID, start: s, end: e))
            }

            if !segs.isEmpty {
                out[sentenceID] = segs.sorted { $0.start < $1.start }
            }
        }

        return out
    }
}

// Put this BELOW PracticeView in the same file.
// If you put it in a separate file, remove `private`.
private struct PracticeSentenceFlagRow: View {
    let chunk: SentenceChunk
    let index: Int
    let itemID: UUID

    @ObservedObject var transcriptVM: TranscriptViewModel

    private var isFlagged: Bool {
        transcriptVM.isFlagged(sentenceID: chunk.id)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)

            Text(transcriptVM.displayText(for: chunk))
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                transcriptVM.toggleFlag(itemID: itemID, sentenceID: chunk.id)
            } label: {
                Image(systemName: isFlagged ? "flag.fill" : "flag")
                    .font(.headline)
                    .foregroundStyle(isFlagged ? Color.orange : Color.secondary)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(.tertiarySystemFill))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
