import SwiftUI

struct PracticeView: View {
    let item: AudioItem
    let onClose: () -> Void

    @EnvironmentObject private var library: AudioLibrary

    @StateObject private var transcriptVM = TranscriptViewModel()
    @StateObject private var playback = AudioPlaybackManager()
    @StateObject private var stats: PracticeStatsManager

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

    // Collapsibles
    @State private var showFullscreenControls: Bool = false        // hidden by default
    @State private var showFlaggingSentences: Bool = false         // collapsed by default

    // Mode details (collapsed by default)
    @State private var showWordsDetails: Bool = false
    @State private var showSentenceDetails: Bool = false

    init(item: AudioItem, onClose: @escaping () -> Void) {
        self.item = item
        self.onClose = onClose
        _stats = StateObject(wrappedValue: PracticeStatsManager(itemID: item.id, itemTitle: item.scriptName))
    }

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

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                ScrollView {
                    VStack(spacing: 18) {
                        titleCard
                        PracticeStatsCardView(stats: stats)

                        Text("Shadowing practice")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 2)
                            .padding(.top, 2)

                        wordsShadowingCard
                        sentenceShadowingCard
                        partialPlayCard
                        flaggingSentencesCard
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 16)
                }
            }
        }
        .onAppear {
            transcriptVM.loadIfAvailable(itemID: item.id)
            applySavedPlaybackSettings()
            Task { await stats.refresh() }
        }
        .onDisappear {
            stats.forceStopIfRunning()
        }

        // ✅ Start/stop timer based on actual playback running state
        .onChange(of: playback.isPartialPlaying) { isRunning in
            stats.handlePlaybackRunningChanged(isRunning: isRunning)
        }

        // Persist settings changes
        .onChange(of: playbackFontScale) { _ in persistPlaybackSettings() }
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

    // MARK: - Top UI

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                playback.stop()
                stats.forceStopIfRunning()
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

            HStack(spacing: 8) {
                Image(systemName: "book.open")
                    .foregroundStyle(.secondary)
                Text("My Reading Practice")
                    .font(.headline)
                    .foregroundStyle(.primary)
            }

            Spacer()

            Color.clear
                .frame(width: 44, height: 1)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    // MARK: - Cards

    private var titleCard: some View {
        card {
            HStack {
                Spacer(minLength: 0)
                Text(item.scriptName.isEmpty ? "Practice" : item.scriptName)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.orange)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
        }
    }



    private var wordsShadowingCard: some View {
        let wordSegs = buildWordSegments(flaggedOnly: flaggedOnly)
        let hasWords = !wordSegs.isEmpty

        return card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        shadowingIconCombo
                        Text("Words")
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }

                    Spacer()

                    Button {
                        guard hasWords else { return }
                        withAnimation(.easeInOut(duration: 0.15)) {
                            wordsShadowingOn.toggle()
                        }
                    } label: {
                        modeStatusPill(
                            isOn: wordsShadowingOn && hasWords,
                            repeats: wordRepeats,
                            disabled: !hasWords
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!hasWords)

                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            showWordsDetails.toggle()
                        }
                    } label: {
                        Image(systemName: showWordsDetails ? "chevron.up" : "chevron.down")
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30, alignment: .center)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                if !hasWords {
                    Text("No hard words marked (🚀) in Edit yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if showWordsDetails, hasWords {
                    VStack(alignment: .leading, spacing: 12) {
                        repeatsSelector(
                            title: "Repetitions",
                            selection: $wordRepeats,
                            options: [1, 2, 3, 4, 5]
                        )

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Speaking silence adjustment")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Slider(value: $wordSilenceMultiplier, in: 0.5...15.0, step: 0.1)
                            Text("\(Int(wordSilenceMultiplier * 100))%")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .transition(emergeTransition)
                }
            }
            .animation(.easeInOut(duration: 0.22), value: showWordsDetails)
        }
    }

    private var sentenceShadowingCard: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        shadowingIconCombo
                        Text("Sentences")
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }

                    Spacer()

                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            sentenceShadowingOn.toggle()
                        }
                    } label: {
                        modeStatusPill(
                            isOn: sentenceShadowingOn,
                            repeats: sentenceRepeats,
                            disabled: false
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            showSentenceDetails.toggle()
                        }
                    } label: {
                        Image(systemName: showSentenceDetails ? "chevron.up" : "chevron.down")
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30, alignment: .center)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                if showSentenceDetails {
                    VStack(alignment: .leading, spacing: 12) {
                        repeatsSelector(
                            title: "Repetitions",
                            selection: $sentenceRepeats,
                            options: [1, 2, 3]
                        )

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Speaking silence adjustment")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Slider(value: $sentenceSilenceMultiplier, in: 0.5...2.0, step: 0.1)
                            Text("\(Int(sentenceSilenceMultiplier * 100))%")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .transition(emergeTransition)
                }
            }
            .animation(.easeInOut(duration: 0.22), value: showSentenceDetails)
        }
    }

    private var partialPlayCard: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        showFullscreenControls.toggle()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(.secondary)
                        Text("Playback display")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: showFullscreenControls ? "chevron.up" : "chevron.down")
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if showFullscreenControls {
                    VStack(alignment: .leading, spacing: 12) {
                        Button {
                            showPlaybackScreen = true
                        } label: {
                            Label("Open Fullscreen", systemImage: "rectangle.inset.filled.and.person.filled")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

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
                    .transition(emergeTransition)
                }

                Divider().opacity(0.6)

                Toggle(isOn: $flaggedOnly) {
                    Label("Flagged Only", systemImage: "flag.fill")
                }
                .font(.subheadline)

                Toggle(isOn: $sentencesPauseOnly) {
                    Label("Sentences pause only", systemImage: "pause.circle")
                }
                .font(.subheadline)

                HStack(spacing: 12) {
                    Button {
                        guard FileManager.default.fileExists(atPath: storedMP3URL.path) else { return }
                        guard hasTranscript else { return }

                        let chunksToPlay = filteredSentenceChunksForPartial
                        guard !chunksToPlay.isEmpty else { return }

                        // ✅ Only prepare a new session when we are starting (not stopping)
                        let wasRunning = playback.isPartialPlaying || playback.isPlaying || playback.isPaused
                        if !wasRunning {
                            let mode: PracticeMode = {
                                if wordsShadowingOn && sentenceShadowingOn { return .mixed }
                                if wordsShadowingOn { return .words }
                                if sentenceShadowingOn { return .sentences }
                                return .partial
                            }()

                            stats.prepareNextSession(
                                mode: mode,
                                flaggedOnly: flaggedOnly,
                                wordRepeats: wordRepeats,
                                sentenceRepeats: sentenceRepeats
                            )
                        }

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
                        Label(playback.isPartialPlaying ? "Stop" : "Start",
                              systemImage: playback.isPartialPlaying ? "stop.fill" : "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!FileManager.default.fileExists(atPath: storedMP3URL.path) || !hasTranscript)

                    Button {
                        if sentenceShadowingOn && !wordsShadowingOn {
                            sentenceRepeats = min(3, sentenceRepeats + 1)
                        } else if wordsShadowingOn && !sentenceShadowingOn {
                            wordRepeats = min(5, wordRepeats + 1)
                        } else if sentenceShadowingOn && wordsShadowingOn {
                            sentenceRepeats = min(3, sentenceRepeats + 1)
                        }
                    } label: {
                        Label("Repeat +", systemImage: "repeat")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .animation(.easeInOut(duration: 0.22), value: showFullscreenControls)
        }
    }

    private var flaggingSentencesCard: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        showFlaggingSentences.toggle()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "flag.fill")
                            .foregroundStyle(.secondary)
                        Text("Flagging Sentences")
                            .font(.headline)
                        Spacer()
                        Image(systemName: showFlaggingSentences ? "chevron.up" : "chevron.down")
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if showFlaggingSentences {
                    if transcriptVM.sentenceChunks.isEmpty {
                        Text("No transcript yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .transition(emergeTransition)
                    } else {
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
                        .transition(emergeTransition)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.22), value: showFlaggingSentences)
        }
    }

    // MARK: - Icon combo for both words/sentences

    private var shadowingIconCombo: some View {
        HStack(spacing: 4) {
            Image(systemName: "person.wave.2.fill")
            Image(systemName: "repeat")
        }
        .foregroundStyle(.secondary)
    }

    // MARK: - UI building blocks

    private var emergeTransition: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
    }

    private func modeStatusPill(isOn: Bool, repeats: Int, disabled: Bool) -> some View {
        let bg = disabled ? Color(.tertiarySystemFill) : (isOn ? Color.blue.opacity(0.18) : Color(.tertiarySystemFill))
        let fg = disabled ? Color.secondary : (isOn ? Color.blue : Color.secondary)
        let icon = isOn ? "checkmark.circle.fill" : "circle"

        return HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(fg)
            Text("x\(repeats)")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(fg)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Capsule(style: .continuous).fill(bg))
        .overlay(
            Capsule(style: .continuous)
                .stroke(isOn && !disabled ? Color.blue.opacity(0.55) : Color.clear, lineWidth: 1)
        )
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
    }

    private func repeatsSelector(title: String, selection: Binding<Int>, options: [Int]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                ForEach(options, id: \.self) { v in
                    let selected = (selection.wrappedValue == v)

                    Button { selection.wrappedValue = v } label: {
                        Text("\(v)x")
                            .font(.subheadline)
                            .fontWeight(selected ? .semibold : .regular)
                            .foregroundStyle(selected ? Color.blue : Color.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(selected ? Color.blue.opacity(0.32) : Color(.tertiarySystemFill))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(selected ? Color.blue.opacity(0.75) : Color.clear, lineWidth: 1.2)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Settings persistence

    private func applySavedPlaybackSettings() {
        let s = transcriptVM.playbackSettings.clamped()
        playbackFontScale = s.playbackFontScale

        sentenceShadowingOn = s.repeatPracticeEnabled
        sentenceRepeats = s.practiceRepeats
        sentenceSilenceMultiplier = s.practiceSilenceMultiplier
        sentencesPauseOnly = s.sentencesPauseOnly
        flaggedOnly = s.flaggedOnly

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

    // MARK: - Word segments

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

// Keep this below PracticeView
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

            Text(transcriptVM.attributedDisplayText(for: chunk))
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
