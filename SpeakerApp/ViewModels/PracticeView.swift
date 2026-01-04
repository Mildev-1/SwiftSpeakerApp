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
    @State private var sentenceRepeats: Int = 3
    @State private var sentenceSilenceMultiplier: Double = 1.0
    @State private var sentencesPauseOnly: Bool = false

    // Word shadowing
    @State private var wordsShadowingOn: Bool = false
    @State private var wordRepeats: Int = 3
    @State private var wordSilenceMultiplier: Double = 1.0

    // Partial play controls
    @State private var flaggedOnly: Bool = false

    // Card expansion
    @State private var showPlaybackDisplaySettings: Bool = false
    @State private var showWordsCard: Bool = false
    @State private var showSentencesCard: Bool = false
    @State private var showFlaggingSentences: Bool = false // collapsed by default

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

    private var currentPlaybackSettings: PlaybackSettings {
        PlaybackSettings(
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
    }

    private var estimatedNextPracticeSeconds: Double? {
        let settings = currentPlaybackSettings
        let chunks = filteredSentenceChunksForPartial
        guard !chunks.isEmpty else { return nil }

        let mode: PracticeMode
        if settings.wordShadowingEnabled && settings.repeatPracticeEnabled {
            mode = .mixed
        } else if settings.wordShadowingEnabled {
            mode = .words
        } else if settings.repeatPracticeEnabled {
            mode = .sentences
        } else {
            mode = .partial
        }

        // Build segments the same way Start uses them (respecting flaggedOnly).
        let wordSegs = buildWordSegments(flaggedOnly: settings.flaggedOnly)
        let wordSegsBySentence = buildWordSegmentsBySentence(flaggedOnly: settings.flaggedOnly)

        return PracticeTimeEstimator.estimateSeconds(
            mode: mode,
            chunks: chunks,
            manualCutsBySentence: transcriptVM.manualCutsBySentence,
            fineTunesBySubchunk: transcriptVM.fineTunesBySubchunk,
            wordSegments: wordSegs,
            wordSegmentsBySentence: wordSegsBySentence,
            sentenceRepeats: settings.practiceRepeats,
            sentenceSilenceMultiplier: settings.practiceSilenceMultiplier,
            sentencesPauseOnly: settings.sentencesPauseOnly,
            wordRepeats: settings.wordPracticeRepeats,
            wordSilenceMultiplier: settings.wordPracticeSilenceMultiplier,
            wordOuterLoops: (mode == .words ? playback.loopCount : 1)
        )
    }

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                ScrollView {
                    VStack(spacing: 14) {
                        titleCard

                        PracticeStatsCardView(stats: stats, estimatedNextSeconds: estimatedNextPracticeSeconds)

                        Text("Shadowing practice")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)

                        wordsCard
                        sentencesCard
                        partialPlayCard
                        flaggingSentencesCard
                    }
                    .padding(.vertical, 14)
                }
            }
        }
        .onAppear {
            transcriptVM.loadIfAvailable(itemID: item.id)
            hydrateUIFromSavedSettings()
            Task { await stats.refresh() }
        }
        .task {
            await stats.refresh()
        }
        .sheet(isPresented: $showPlaybackScreen) {
            PlaybackScreenView(
                item: item,
                playback: playback,
                transcriptVM: transcriptVM,
                isPresented: $showPlaybackScreen
            )
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
    }

    // MARK: - Top bar / cards (UNCHANGED below)

    private var topBar: some View { /* ... existing code ... */ EmptyView() }
    private var titleCard: some View { /* ... existing code ... */ EmptyView() }
    private var wordsCard: some View { /* ... existing code ... */ EmptyView() }
    private var sentencesCard: some View { /* ... existing code ... */ EmptyView() }
    private var partialPlayCard: some View { /* ... existing code ... */ EmptyView() }
    private var flaggingSentencesCard: some View { /* ... existing code ... */ EmptyView() }

    private func hydrateUIFromSavedSettings() {
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
        let s = currentPlaybackSettings
        transcriptVM.setPlaybackSettings(itemID: item.id, s)
        transcriptVM.saveCutPlan(itemID: item.id)
    }

    // MARK: - Word segments

    private func buildWordSegments(flaggedOnly: Bool) -> [AudioPlaybackManager.TimedSegment] {
        let boundsBySentence: [String: (Double, Double)] = Dictionary(
            uniqueKeysWithValues: transcriptVM.sentenceChunks.map { ($0.id, ($0.start, $0.end)) }
        )

        var segs: [AudioPlaybackManager.TimedSegment] = []
        segs.reserveCapacity(64)

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

                segs.append(.init(sentenceID: sentenceID, start: s, end: e))
            }
        }

        return segs.sorted { $0.start < $1.start }
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
