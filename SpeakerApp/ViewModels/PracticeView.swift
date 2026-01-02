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

    // Repeat practice UI (persisted)
    @State private var isRepeatPracticeEnabled: Bool = false
    @State private var practiceRepeats: Int = 2
    @State private var practiceSilenceMultiplier: Double = 1.0
    @State private var sentencesPauseOnly: Bool = false

    // ✅ NEW: Flagged-only toggle (persisted via PlaybackSettings)
    @State private var flaggedOnly: Bool = false

    // Font scale slider for Full Screen Playback (persisted per item)
    @State private var playbackFontScale: Double = 1.0

    @State private var showPlaybackScreen: Bool = false

    private var storedMP3URL: URL {
        AudioStorage.shared.urlForStoredFile(relativePath: item.storedRelativePath)
    }

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                topBar

                ScrollView {
                    VStack(spacing: 18) {
                        headerSection
                        playbackSection
                        sentencesSection
                        errorSection
                    }
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
                }
            }
        }
        .onAppear {
            transcriptVM.loadIfAvailable(itemID: item.id)
            playback.loadIfNeeded(url: storedMP3URL)

            let s = transcriptVM.playbackSettings.clamped()
            isRepeatPracticeEnabled = s.repeatPracticeEnabled
            practiceRepeats = s.practiceRepeats
            practiceSilenceMultiplier = s.practiceSilenceMultiplier
            sentencesPauseOnly = s.sentencesPauseOnly
            playbackFontScale = s.playbackFontScale
            flaggedOnly = s.flaggedOnly
        }
        .onChange(of: isRepeatPracticeEnabled) { _ in persistPlaybackSettings() }
        .onChange(of: practiceRepeats) { _ in persistPlaybackSettings() }
        .onChange(of: practiceSilenceMultiplier) { _ in persistPlaybackSettings() }
        .onChange(of: sentencesPauseOnly) { _ in persistPlaybackSettings() }
        .onChange(of: playbackFontScale) { _ in persistPlaybackSettings() }
        .onChange(of: flaggedOnly) { _ in persistPlaybackSettings() }

        .fullScreenCover(isPresented: $showPlaybackScreen) {
            PlaybackScreenView(
                item: item,
                playback: playback,
                transcriptVM: transcriptVM,
                isPresented: $showPlaybackScreen
            )
        }
    }

    private func persistPlaybackSettings() {
        let s = PlaybackSettings(
            repeatPracticeEnabled: isRepeatPracticeEnabled,
            practiceRepeats: practiceRepeats,
            practiceSilenceMultiplier: practiceSilenceMultiplier,
            sentencesPauseOnly: sentencesPauseOnly,
            playbackFontScale: playbackFontScale,
            flaggedOnly: flaggedOnly
        ).clamped()
        transcriptVM.setPlaybackSettings(itemID: item.id, s)
    }

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

    // Requirement: show the grid title only (no filename)
    private var headerSection: some View {
        VStack(spacing: 10) {
            Text(item.scriptName)
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
        }
    }

    private var playbackSection: some View {
        VStack(spacing: 12) {

            // 1) Playback font size slider
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

            // 2) Repeat practice toggle + uncovered options + ✅ Flagged Only
            VStack(spacing: 10) {
                Toggle("Repeat practice", isOn: $isRepeatPracticeEnabled)
                    .toggleStyle(.switch)

                if isRepeatPracticeEnabled {
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
                            Slider(value: $practiceSilenceMultiplier, in: 0.2...3.0, step: 0.05)
                        }

                        Toggle("Sentences pause only", isOn: $sentencesPauseOnly)
                            .toggleStyle(.switch)
                    }
                    .padding(.top, 6)
                }

                // ✅ NEW: Flagged Only toggle (placed at bottom of this card, as requested)
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

            // Full-file Play / Stop
            HStack(spacing: 12) {
                Button { playback.togglePlay(url: storedMP3URL) } label: {
                    Label(
                        playback.isPlaying ? "Pause" : "Play",
                        systemImage: playback.isPlaying ? "pause.fill" : "play.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!FileManager.default.fileExists(atPath: storedMP3URL.path))

                Button { playback.stop() } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!playback.isPlaying && !playback.isPartialPlaying)
            }
            .padding(12)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.quaternary, lineWidth: 1)
            )

            // 3) Partial play + Repeat × button (loop count)
            HStack(spacing: 12) {
                Button {
                    let willStart = !playback.isPartialPlaying

                    let mode: AudioPlaybackManager.PartialPlaybackMode =
                        isRepeatPracticeEnabled
                        ? .repeatPractice(
                            repeats: practiceRepeats,
                            silenceMultiplier: practiceSilenceMultiplier,
                            sentencesPauseOnly: sentencesPauseOnly
                        )
                        : .beepBetweenCuts

                    // ✅ apply Flagged Only filter when enabled
                    let chunksToPlay: [SentenceChunk] = {
                        if flaggedOnly {
                            return transcriptVM.sentenceChunks.filter { transcriptVM.flaggedSentenceIDs.contains($0.id) }
                        } else {
                            return transcriptVM.sentenceChunks
                        }
                    }()

                    // If flaggedOnly is ON but nothing is flagged, do nothing.
                    guard !chunksToPlay.isEmpty else { return }

                    playback.togglePartialPlay(
                        url: storedMP3URL,
                        chunks: chunksToPlay,
                        manualCutsBySentence: transcriptVM.manualCutsBySentence,
                        fineTunesBySubchunk: transcriptVM.fineTunesBySubchunk,
                        mode: mode
                    )

                    // Full-screen playback is only launched from PracticeView
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
            .padding(12)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.quaternary, lineWidth: 1)
            )

            if transcriptVM.sentenceChunks.isEmpty {
                Text("No transcript available. Use Edit → Extract Text to enable partial practice.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if flaggedOnly && transcriptVM.flaggedSentenceIDs.isEmpty {
                Text("Flagged Only is ON, but no sentences are flagged.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // ✅ NEW: Sentences list for flagging (no edit popup)
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
            if let msg = playback.errorMessage {
                Text(msg)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
        }
    }
}
