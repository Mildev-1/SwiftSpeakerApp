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

                        // Playback controls (unchanged)
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
                                playback.cycleLoopCount() // default now should be 10 in manager
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

                        // ✅ Transcribe section
                        VStack(spacing: 10) {
                            HStack {
                                Button {
                                    Task {
                                        await transcriptVM.transcribeFromMP3(
                                            mp3URL: storedMP3URL,
                                            languageCode: "en"   // "es" for Spanish, "pt" for Portuguese
                                        )
                                    }
                                } label: {
                                    Label(transcriptVM.isTranscribing ? "Transcribing…" : "Extract Text",
                                          systemImage: "text.quote")
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(transcriptVM.isTranscribing)

                                Spacer()

                                Text("Words: \(transcriptVM.words.count)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            // ✅ Add this row
                            HStack {
                                Button("Reset Whisper Models") {
                                    WhisperModelReset.resetAll()
                                }
                                .buttonStyle(.bordered)

                                Spacer()

                                Text("Use if model download got stuck")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            

                            if let err = transcriptVM.errorMessage {
                                Text(err)
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            // Scrollable text field
                            TextEditor(text: .constant(transcriptVM.transcriptText))
                                .font(.body)
                                .frame(minHeight: 220)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(.quaternary, lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .padding(.top, 6)

                        Spacer(minLength: 30)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .frame(maxWidth: 700)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .onAppear {
            playback.loadIfNeeded(url: storedMP3URL)
        }
        .onDisappear {
            playback.stop()
        }
    }
}
