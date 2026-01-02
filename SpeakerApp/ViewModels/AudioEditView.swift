import SwiftUI
#if os(macOS)
import AppKit
#endif

struct AudioEditView: View {
    let item: AudioItem
    let onClose: () -> Void

    @StateObject private var playback = AudioPlaybackManager()
    @StateObject private var transcriptVM = TranscriptViewModel()

    @State private var selectedChunk: SentenceChunk? = nil

    // Repeat practice UI (persisted)
    @State private var isRepeatPracticeEnabled: Bool = false
    @State private var practiceRepeats: Int = 2
    @State private var practiceSilenceMultiplier: Double = 1.0
    @State private var sentencesPauseOnly: Bool = false

    // ✅ full-screen playback screen
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
                        transcriptSection
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
        }
        .onChange(of: isRepeatPracticeEnabled) { _ in persistPlaybackSettings() }
        .onChange(of: practiceRepeats) { _ in persistPlaybackSettings() }
        .onChange(of: practiceSilenceMultiplier) { _ in persistPlaybackSettings() }
        .onChange(of: sentencesPauseOnly) { _ in persistPlaybackSettings() }

        .sheet(item: $selectedChunk) { chunk in
            SentenceEditSheet(
                itemID: item.id,
                chunk: chunk,
                audioURL: storedMP3URL,
                words: transcriptVM.words,
                transcriptVM: transcriptVM
            )
        }

        // ✅ Full screen playback view (auto-scroll happens there)
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
            sentencesPauseOnly: sentencesPauseOnly
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
                    .font(.title3)
                    .padding(10)
            }
            .buttonStyle(.bordered)

            Spacer()
            Text("Edit").font(.headline)
            Spacer()

            Rectangle().fill(.clear).frame(width: 44, height: 44)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var headerSection: some View {
        VStack(spacing: 10) {
            Text(item.scriptName)
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)

            Text(item.originalFileName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .truncationMode(.tail)
                .padding(.horizontal, 8)
        }
    }

    private var playbackSection: some View {
        VStack(spacing: 12) {
            // Repeat practice toggle + controls (persisted)
            VStack(spacing: 10) {
                Toggle(isOn: $isRepeatPracticeEnabled) {
                    Text("Repeat practice")
                        .font(.callout)
                        .fontWeight(.semibold)
                }
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
                            Slider(value: $practiceSilenceMultiplier, in: 0.5...2.0)
                        }

                        Toggle(isOn: $sentencesPauseOnly) {
                            Text("Sentences pause only")
                                .font(.callout)
                                .fontWeight(.semibold)
                        }
                        .toggleStyle(.switch)
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

            // Play / Stop (full file)
            HStack(spacing: 12) {
                Button { playback.togglePlay(url: storedMP3URL) } label: {
                    Label(playback.isPlaying ? "Pause" : "Play",
                          systemImage: playback.isPlaying ? "pause.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button { playback.stop() } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            // Partial Play + file loop
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

                    playback.togglePartialPlay(
                        url: storedMP3URL,
                        chunks: transcriptVM.sentenceChunks,
                        manualCutsBySentence: transcriptVM.manualCutsBySentence,
                        fineTunesBySubchunk: transcriptVM.fineTunesBySubchunk,
                        mode: mode
                    )

                    // ✅ Open playback screen only when starting
                    if willStart {
                        showPlaybackScreen = true
                    }
                } label: {
                    Label(playback.isPartialPlaying ? "Partial Stop" : "Partial Play", systemImage: "scissors")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(transcriptVM.sentenceChunks.isEmpty || transcriptVM.isTranscribing)

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
    }

    private var transcriptSection: some View {
        VStack(spacing: 10) {
            // ✅ Back to embedded scroll list (no auto-scroll here)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if transcriptVM.sentenceChunks.isEmpty {
                        Text(transcriptVM.isTranscribing ? "Transcribing…" : "No transcript yet.")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(Array(transcriptVM.sentenceChunks.enumerated()), id: \.element.id) { idx, chunk in
                            let isActive = (playback.currentSentenceID == chunk.id)
                            let textToShow = transcriptVM.displayText(for: chunk)

                            Button { selectedChunk = chunk } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Text("\(idx + 1).")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 28, alignment: .trailing)

                                    Text(textToShow)
                                        .foregroundStyle(isActive ? .orange : .primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(isActive ? .orange.opacity(0.10) : Color.clear)
                                )
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                        }
                    }
                }
                .padding(12)
            }
            .frame(height: 320)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.quaternary, lineWidth: 1)
            )

            if !transcriptVM.statusText.isEmpty {
                Text(transcriptVM.statusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let err = transcriptVM.errorMessage {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button {
                    Task {
                        await transcriptVM.transcribeFromMP3(
                            itemID: item.id,
                            mp3URL: storedMP3URL,
                            languageCode: "en",
                            model: "base",
                            force: transcriptVM.hasCachedTranscript
                        )
                    }
                } label: {
                    Label(
                        transcriptVM.isTranscribing
                        ? "Transcribing…"
                        : (transcriptVM.hasCachedTranscript ? "Re-Transcribe" : "Extract Text"),
                        systemImage: "text.quote"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(transcriptVM.isTranscribing)

                Spacer()

                Text("Words: \(transcriptVM.words.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 2)
        }
        .padding(.top, 6)
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
