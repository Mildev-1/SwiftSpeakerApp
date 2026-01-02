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
        }
        .sheet(item: $selectedChunk) { chunk in
            SentenceEditSheet(
                itemID: item.id,
                chunk: chunk,
                audioURL: storedMP3URL,
                words: transcriptVM.words,
                transcriptVM: transcriptVM
            )
        }
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
        VStack(spacing: 10) {
            VStack(spacing: 10) {
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

                HStack(spacing: 12) {
                    Button {
                        playback.togglePartialPlay(
                            url: storedMP3URL,
                            chunks: transcriptVM.sentenceChunks,
                            manualCutsBySentence: transcriptVM.manualCutsBySentence,
                            fineTunesBySubchunk: transcriptVM.fineTunesBySubchunk
                        )
                    } label: {
                        Label(playback.isPartialPlaying ? "Partial Stop" : "Partial Play",
                              systemImage: "scissors")
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

            if playback.isPartialPlaying {
                Text("Partial: \(playback.partialIndex)/\(max(playback.partialTotal, 1))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var transcriptSection: some View {
        VStack(spacing: 10) {
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

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if transcriptVM.sentenceChunks.isEmpty {
                        Text("No transcript yet.")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(Array(transcriptVM.sentenceChunks.enumerated()), id: \.element.id) { idx, chunk in
                            let isActive = (playback.currentSentenceID == chunk.id)
                            let textToShow = transcriptVM.displayText(for: chunk)

                            Button {
                                selectedChunk = chunk
                            } label: {
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
                            .animation(.easeInOut(duration: 0.15), value: playback.currentSentenceID)
                        }
                    }
                }
                .padding(12)
            }
            .frame(minHeight: 260)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.quaternary, lineWidth: 1)
            )
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
