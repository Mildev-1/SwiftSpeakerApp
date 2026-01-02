import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Practice-only screen for playback options and partial / repeat practice.
struct PracticeView: View {
    let item: AudioItem
    let onClose: () -> Void

    @StateObject private var playback = AudioPlaybackManager()
    @StateObject private var transcriptVM = TranscriptViewModel()

    // Sentence shadowing UI (persisted)
    @State private var isSentenceShadowingEnabled: Bool = false
    @State private var practiceRepeats: Int = 2
    @State private var practiceSilenceMultiplier: Double = 1.0
    @State private var sentencesPauseOnly: Bool = false

    // Flags filter (persisted)
    @State private var flaggedOnly: Bool = false

    // Words shadowing UI (persisted)
    @State private var isWordsShadowingEnabled: Bool = false
    @State private var wordPracticeRepeats: Int = 2
    @State private var wordPracticeSilenceMultiplier: Double = 1.5

    // Font scale slider for Full Screen Playback (persisted per item)
    @State private var playbackFontScale: Double = 1.0

    @State private var showPlaybackScreen: Bool = false

    private var storedMP3URL: URL {
        AudioStorage.shared.urlForStoredFile(relativePath: item.storedRelativePath)
    }

    var body: some View {
        ZStack {
            background

            VStack(spacing: 10) {
                topBar

                ScrollView {
                    VStack(spacing: 12) {
                        // 0) Title
                        headerSection

                        // 1) General play/stop buttons card
                        fullFilePlayStopCard

                        // 2) Playback font size slider card
                        playbackFontSizeCard

                        // 3) Sentence Shadowing / Flagged Only card
                        sentenceShadowingCard

                        // 4) Words Shadowing card
                        wordsShadowingCard

                        // 5) Partial play, repeat × card
                        partialPlayCard

                        // 6) Sentences list + flags
                        sentencesSection

                        errorSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 22)
                }
            }
        }
        .onAppear {
            transcriptVM.loadIfAvailable(itemID: item.id)

            let s = transcriptVM.playbackSettings.clamped()
            isSentenceShadowingEnabled = s.repeatPracticeEnabled
            practiceRepeats = s.practiceRepeats
            practiceSilenceMultiplier = s.practiceSilenceMultiplier
            sentencesPauseOnly = s.sentencesPauseOnly
            playbackFontScale = s.playbackFontScale
            flaggedOnly = s.flaggedOnly

            isWordsShadowingEnabled = s.wordShadowingEnabled
            wordPracticeRepeats = s.wordPracticeRepeats
            wordPracticeSilenceMultiplier = s.wordPracticeSilenceMultiplier

            // enforce exclusivity on load
            if isSentenceShadowingEnabled && isWordsShadowingEnabled {
                isWordsShadowingEnabled = false
            }
        }
        .onDisappear {
            playback.stop()
        }
        .onChange(of: isSentenceShadowingEnabled) { newValue in
            if newValue { isWordsShadowingEnabled = false }
            persistPlaybackSettings()
        }
        .onChange(of: practiceRepeats) { _ in persistPlaybackSettings() }
        .onChange(of: practiceSilenceMultiplier) { _ in persistPlaybackSettings() }
        .onChange(of: sentencesPauseOnly) { _ in persistPlaybackSettings() }
        .onChange(of: playbackFontScale) { _ in persistPlaybackSettings() }
        .onChange(of: flaggedOnly) { _ in persistPlaybackSettings() }

        .onChange(of: isWordsShadowingEnabled) { newValue in
            if newValue { isSentenceShadowingEnabled = false }
            persistPlaybackSettings()
        }
        .onChange(of: wordPracticeRepeats) { _ in persistPlaybackSettings() }
        .onChange(of: wordPracticeSilenceMultiplier) { _ in persistPlaybackSettings() }

        .fullScreenCover(isPresented: $showPlaybackScreen) {
            PlaybackScreenView(
                item: item,
                playback: playback,
                transcriptVM: transcriptVM,
                isPresented: $showPlaybackScreen
            )
        }
    }

    // MARK: - Persistence

    private func persistPlaybackSettings() {
        // enforce mutual exclusivity in saved state
        let sentenceOn = isSentenceShadowingEnabled && !isWordsShadowingEnabled
        let wordsOn = isWordsShadowingEnabled && !isSentenceShadowingEnabled

        let s = PlaybackSettings(
            repeatPracticeEnabled: sentenceOn,
            practiceRepeats: practiceRepeats,
            practiceSilenceMultiplier: practiceSilenceMultiplier,
            sentencesPauseOnly: sentencesPauseOnly,
            playbackFontScale: playbackFontScale,
            flaggedOnly: flaggedOnly,
            wordShadowingEnabled: wordsOn,
            wordPracticeRepeats: wordPracticeRepeats,
            wordPracticeSilenceMultiplier: wordPracticeSilenceMultiplier
        ).clamped()

        transcriptVM.setPlaybackSettings(itemID: item.id, s)
    }

    // MARK: - UI pieces

    private var background: some View {
        Group {
            #if os(macOS)
            Color(NSColor.windowBackgroundColor)
            #else
            Color(.systemBackground)
            #endif
        }
        .ignoresSafeArea()
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                playback.stop()
                onClose()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.bordered)

            Spacer()
            Text("Practice").font(.headline)
            Spacer()

            Rectangle().fill(.clear).frame(width: 44, height: 44)
        }
        .padding(.horizontal)
        .padding(.top, 12)
    }

    // 0) Title
    private var headerSection: some View {
        Text(item.scriptName)
            .font(.title2.weight(.semibold))
            .multilineTextAlignment(.center)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }

    // 1) full file play/stop
    private var fullFilePlayStopCard: some View {
        HStack(spacing: 12) {
            Button {
                playback.togglePlay(url: storedMP3URL)
            } label: {
                Label(playback.isPlaying ? "Pause" : "Play",
                      systemImage: playback.isPlaying ? "pause.fill" : "play.fill")
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!FileManager.default.fileExists(atPath: storedMP3URL.path))
        }
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        )
    }

    // 2) font slider
    private var playbackFontSizeCard: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Playback font size")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(playbackFontScale * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Slider(value: $playbackFontScale, in: 1.0...2.2, step: 0.05)
        }
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        )
    }

    // 3) Sentence Shadowing + Flagged Only
    private var sentenceShadowingCard: some View {
        VStack(spacing: 10) {
            Toggle("Sentence Shadowing", isOn: $isSentenceShadowingEnabled)
                .toggleStyle(.switch)

            if isSentenceShadowingEnabled {
                VStack(spacing: 10) {
                    Picker("Repeats", selection: $practiceRepeats) {
                        Text("1").tag(1)
                        Text("2").tag(2)
                        Text("3").tag(3)
                    }
                    .pickerStyle(.segmented)

                    VStack(spacing: 6) {
                        HStack {
                            Text("Silence multiplier")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("×\(practiceSilenceMultiplier, specifier: "%.2f")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $practiceSilenceMultiplier, in: 0.5...2.0, step: 0.05)
                    }

                    Toggle("Sentences pause only", isOn: $sentencesPauseOnly)
                        .toggleStyle(.switch)
                }
                .padding(.top, 6)
            }

            Divider().opacity(0.35)

            Toggle("Flagged Only", isOn: $flaggedOnly)
                .toggleStyle(.switch)
                .padding(.top, 6)
        }
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        )
    }

    // 4) Words Shadowing
    private var wordsShadowingCard: some View {
        let wordSegs = buildWordSegments(flaggedOnly: flaggedOnly)

        return VStack(spacing: 10) {
            Toggle("Words Shadowing", isOn: $isWordsShadowingEnabled)
                .toggleStyle(.switch)

            if isWordsShadowingEnabled {
                VStack(spacing: 10) {
                    Picker("Repeats", selection: $wordPracticeRepeats) {
                        Text("1").tag(1)
                        Text("2").tag(2)
                        Text("3").tag(3)
                        Text("4").tag(4)
                        Text("5").tag(5)
                    }
                    .pickerStyle(.segmented)

                    VStack(spacing: 6) {
                        HStack {
                            Text("Silence multiplier")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("×\(wordPracticeSilenceMultiplier, specifier: "%.2f")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $wordPracticeSilenceMultiplier, in: 0.2...6.0, step: 0.05)
                    }

                    if wordSegs.isEmpty {
                        Text("No hard words found. Add 🚀 in Edit to create word segments.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    }
                }
                .padding(.top, 6)
            }
        }
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        )
    }

    // 5) Partial play
    private var partialPlayCard: some View {
        let wordSegs = buildWordSegments(flaggedOnly: flaggedOnly)

        return VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    let willStart = !playback.isPartialPlaying

                    if isWordsShadowingEnabled {
                        guard !wordSegs.isEmpty else { return }

                        playback.togglePartialPlayWordSegments(
                            url: storedMP3URL,
                            segments: wordSegs,
                            repeats: wordPracticeRepeats,
                            silenceMultiplier: wordPracticeSilenceMultiplier
                        )
                    } else {
                        let mode: AudioPlaybackManager.PartialPlaybackMode =
                            isSentenceShadowingEnabled
                            ? .repeatPractice(
                                repeats: practiceRepeats,
                                silenceMultiplier: practiceSilenceMultiplier,
                                sentencesPauseOnly: sentencesPauseOnly
                            )
                            : .beepBetweenCuts

                        let chunksToPlay: [SentenceChunk] = {
                            if flaggedOnly {
                                return transcriptVM.sentenceChunks.filter { transcriptVM.flaggedSentenceIDs.contains($0.id) }
                            } else {
                                return transcriptVM.sentenceChunks
                            }
                        }()

                        guard !chunksToPlay.isEmpty else { return }

                        playback.togglePartialPlay(
                            url: storedMP3URL,
                            chunks: chunksToPlay,
                            manualCutsBySentence: transcriptVM.manualCutsBySentence,
                            fineTunesBySubchunk: transcriptVM.fineTunesBySubchunk,
                            mode: mode
                        )
                    }

                    if willStart { showPlaybackScreen = true }
                } label: {
                    Label(playback.isPartialPlaying ? "Partial Stop" : "Partial Play", systemImage: "scissors")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(
                    !FileManager.default.fileExists(atPath: storedMP3URL.path)
                    || transcriptVM.sentenceChunks.isEmpty
                    || (flaggedOnly && transcriptVM.flaggedSentenceIDs.isEmpty)
                    || (isWordsShadowingEnabled && wordSegs.isEmpty)
                )

                Button { playback.cycleLoopCount() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "repeat")
                        Text("×\(playback.loopCount)")
                            .font(.callout)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        )
    }

    // 6) Sentences list + flags (existing)
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
                            let isFlagged = transcriptVM.isFlagged(sentenceID: chunk.id)
                            let textToShow = transcriptVM.displayText(for: chunk)

                            Button {
                                transcriptVM.toggleFlag(itemID: item.id, sentenceID: chunk.id)
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Text("\(idx + 1).")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 34, alignment: .trailing)

                                    Text(textToShow)
                                        .foregroundStyle(.primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(10)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(.thinMaterial)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .stroke(.quaternary, lineWidth: 1)
                                        )

                                    Image(systemName: isFlagged ? "flag.fill" : "flag")
                                        .font(.headline)
                                        .foregroundStyle(isFlagged ? .orange : .secondary)
                                        .frame(width: 28, height: 28, alignment: .center)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(12)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.quaternary, lineWidth: 1)
                )
            }
        }
    }

    private var errorSection: some View {
        Group {
            if let msg = playback.errorMessage, !msg.isEmpty {
                Text(msg)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.thinMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(.quaternary, lineWidth: 1)
                    )
            }
        }
    }

    // MARK: - Word segment extraction (reflection-based, compile-safe)

    private func buildWordSegments(flaggedOnly: Bool) -> [AudioPlaybackManager.TimedSegment] {
        // We try to read these from TranscriptViewModel without depending on concrete types:
        // - hard words dict: [sentenceID: [HardWordLike]]
        // - fine tunes dict: [hardWordID: SegmentFineTuneLike]
        // We accept multiple property names to be robust.

        let hardWordsAny = transcriptVM.reflectValue(
            namedAnyOf: ["hardWordsBySentence", "hardWordsBySentenceID", "hardWordsMapBySentence", "hardWords"]
        )

        guard let dict = hardWordsAny as? AnyDictionary else {
            return []
        }

        // sentence bounds for clamping
        let sentenceBounds: [String: (Double, Double)] = Dictionary(uniqueKeysWithValues: transcriptVM.sentenceChunks.map { ($0.id, ($0.start, $0.end)) })

        // fine tunes dict (optional)
        let fineTunesAny = transcriptVM.reflectValue(
            namedAnyOf: ["fineTunesByHardWord", "fineTunesByHardWordID", "hardWordFineTunes", "hardWordFineTuneByID"]
        )

        let fineTunesDict = fineTunesAny as? AnyDictionary

        var out: [AudioPlaybackManager.TimedSegment] = []

        for (sentenceKeyAny, listAny) in dict.pairs {
            guard let sentenceID = sentenceKeyAny as? String else { continue }
            if flaggedOnly && !transcriptVM.flaggedSentenceIDs.contains(sentenceID) { continue }

            guard let arr = listAny as? [Any] else { continue }

            for hw in arr {
                // extract id/start/end from hard word
                let hwID = Mirror(reflecting: hw).child(namedAnyOf: ["id", "wordID", "uuid"]) as? String
                let baseStart = Mirror(reflecting: hw).child(namedAnyOf: ["baseStart", "start"]) as? Double
                let baseEnd = Mirror(reflecting: hw).child(namedAnyOf: ["baseEnd", "end"]) as? Double

                guard let s0 = baseStart, let e0 = baseEnd else { continue }
                var s = s0
                var e = e0

                // apply fine tune offsets if we can find them
                if let hwID, let fineTunesDict {
                    if let tuneAny = fineTunesDict.value(forKeyAny: hwID) {
                        let m = Mirror(reflecting: tuneAny)
                        let ds = (m.child(namedAnyOf: ["startOffset", "deltaStart", "startDelta"]) as? Double) ?? 0
                        let de = (m.child(namedAnyOf: ["endOffset", "deltaEnd", "endDelta"]) as? Double) ?? 0
                        s += ds
                        e += de
                    }
                }

                // clamp to sentence bounds if available
                if let b = sentenceBounds[sentenceID] {
                    s = max(b.0, min(s, b.1))
                    e = max(b.0, min(e, b.1))
                    if e <= s { e = min(b.1, s + 0.03) }
                } else {
                    if e <= s { e = s + 0.03 }
                }

                out.append(.init(sentenceID: sentenceID, start: s, end: e))
            }
        }

        out.sort { $0.start < $1.start }
        return out
    }
}

// MARK: - Reflection helpers (no dependencies on your model types)

private typealias AnyDictionary = _AnyDictionaryWrapper

private struct _AnyDictionaryWrapper {
    let pairs: [(Any, Any)]
    private let getter: (Any) -> Any?

    init?(_ any: Any) {
        let mirror = Mirror(reflecting: any)

        // Swift Dictionary reflection is not guaranteed stable, so we support two forms:
        // 1) actual Dictionary<K,V> cast handled outside
        // 2) mirror children where each element has key/value
        if mirror.displayStyle == .dictionary {
            var tmp: [(Any, Any)] = []
            for child in mirror.children {
                let tuple = Mirror(reflecting: child.value)
                let key = tuple.child(named: "key")
                let value = tuple.child(named: "value")
                if let key, let value {
                    tmp.append((key, value))
                }
            }
            self.pairs = tmp
            self.getter = { _ in nil }
            return
        }
        return nil
    }

    func value(forKeyAny key: Any) -> Any? {
        // best-effort: linear scan
        for (k, v) in pairs {
            if "\(k)" == "\(key)" { return v }
        }
        return nil
    }
}

private extension TranscriptViewModel {
    func reflectValue(namedAnyOf names: [String]) -> Any? {
        let m = Mirror(reflecting: self)
        for n in names {
            if let v = m.child(named: n) { return v }
        }
        return nil
    }
}

private extension Mirror {
    func child(named name: String) -> Any? {
        children.first(where: { $0.label == name })?.value
    }

    func child(namedAnyOf names: [String]) -> Any? {
        for n in names {
            if let v = child(named: n) { return v }
        }
        return nil
    }
}
