import SwiftUI
#if os(macOS)
import AppKit
#endif

struct AudioEditView: View {
    let item: AudioItem
    let onClose: () -> Void

    @StateObject private var playback = AudioPlaybackManager()
    @StateObject private var transcriptVM = TranscriptViewModel()

    private var storedMP3URL: URL {
        AudioStorage.shared.urlForStoredFile(relativePath: item.storedRelativePath)
    }

    var body: some View {
        ZStack {
            #if os(macOS)
            Color(NSColor.windowBackgroundColor).ignoresSafeArea()
            #else
            Color(.systemBackground).ignoresSafeArea()
            #endif

            VStack(spacing: 0) {
                // Top bar
                HStack {
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
                .padding(.horizontal)
                .padding(.top, 12)

                ScrollView {
                    VStack(spacing: 18) {
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
                            .padding(.horizontal, 16)

                        // Playback controls
                        HStack(spacing: 12) {
                            Button {
                                playback.togglePlay(url: storedMP3URL)
                            } label: {
                                Label(
                                    playback.isPlaying ? "Pause" : "Play",
                                    systemImage: playback.isPlaying ? "pause.fill" : "play.fill"
                                )
                                .frame(minWidth: 110)
                            }
                            .buttonStyle(.borderedProminent)

                            Button {
                                playback.stop()
                            } label: {
                                Label("Stop", systemImage: "stop.fill")
                                    .frame(minWidth: 90)
                            }
                            .buttonStyle(.bordered)

                            Button {
                                playback.cycleLoopCount()
                            } label: {
                                ZStack(alignment: .bottomTrailing) {
                                    Image(systemName: "repeat")
                                        .font(.title3)
                                        .padding(10)

                                    Text("×\(playback.loopCount)")
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.thinMaterial)
                                        .clipShape(Capsule())
                                        .offset(x: 6, y: 6)
                                }
                            }
                            .buttonStyle(.bordered)
                        }

                        // ✅ Transcribe section (cached + re-transcribe)
                        VStack(spacing: 10) {
                            HStack {
                                Button {
                                    Task {
                                        await transcriptVM.transcribeFromMP3(
                                            itemID: item.id,
                                            mp3URL: storedMP3URL,
                                            languageCode: "en",   // "es" or "pt"
                                            model: "base",
                                            force: transcriptVM.hasCachedTranscript // cached -> re-transcribe
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

                            // ✅ Scrollable "textbox" with sentence-per-line formatting (UI only)
                            ScrollView {
                                Text(transcriptVM.formattedTranscriptForDisplay.isEmpty
                                     ? "No transcript yet."
                                     : transcriptVM.formattedTranscriptForDisplay)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                                    .padding(12)
                            }
                            .frame(minHeight: 220)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(.quaternary, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .padding(.top, 6)

                        if let msg = playback.errorMessage {
                            Text(msg)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                                .padding(.top, 4)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
                }
            }
        }
        .onAppear {
            // Load cached transcript immediately if present
            transcriptVM.loadIfAvailable(itemID: item.id)

            // Preload audio (no autoplay)
            playback.loadIfNeeded(url: storedMP3URL)
        }
    }
}

#Preview {
    AudioEditView(item: AudioItem(
        scriptName: "MyScript01",
        originalFileName: "example_long_long_long.mp3",
        storedFileName: "example.mp3",
        storedRelativePath: "example.mp3"
    ), onClose: {})
}
