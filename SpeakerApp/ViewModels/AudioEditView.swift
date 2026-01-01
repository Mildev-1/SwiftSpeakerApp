//
//  AudioEditView.swift
//  SpeakerApp
//

import SwiftUI

struct AudioEditView: View {
    let item: AudioItem
    let onClose: () -> Void

    @StateObject private var playback = AudioPlaybackManager()

    private var storedURL: URL {
        AudioStorage.shared.urlForStoredFile(relativePath: item.storedRelativePath)
    }

    var body: some View {
        ZStack {
            // Fullscreen background
            #if os(macOS)
            Color(NSColor.windowBackgroundColor)
                .ignoresSafeArea()
            #else
            Color(.systemBackground)
                .ignoresSafeArea()
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

                    Text("Edit")
                        .font(.headline)

                    Spacer()

                    // placeholder to balance layout
                    Rectangle()
                        .fill(.clear)
                        .frame(width: 44, height: 44)
                }
                .padding(.horizontal)
                .padding(.top, 12)

                // Content
                VStack(spacing: 18) {
                    Text(item.scriptName)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)

                    Text(item.originalFileName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .truncationMode(.tail)
                        .padding(.horizontal, 16)

                    HStack(spacing: 12) {
                        Button {
                            playback.togglePlay(url: storedURL)
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

                        // Repeat icon only (+1 each tap, default 10, max 50 hardcoded)
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
                        .accessibilityLabel("Repeat \(playback.loopCount) times (max 50)")
                    }

                    if let msg = playback.errorMessage {
                        Text(msg)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                            .padding(.horizontal, 16)
                    }

                    Spacer()
                }
                .padding(.top, 24)
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            // Preload (no autoplay)
            playback.loadIfNeeded(url: storedURL)
        }
        .onDisappear {
            playback.stop()
        }
    }
}

#Preview {
    AudioEditView(
        item: AudioItem(
            scriptName: "MyScript01",
            originalFileName: "example_long_long_long.mp3",
            storedFileName: "example.mp3",
            storedRelativePath: "example.mp3"
        ),
        onClose: {}
    )
}
