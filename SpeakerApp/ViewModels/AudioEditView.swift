//
//  AudioEditView.swift
//  SpeakerApp
//

import SwiftUI

struct AudioEditView: View {
    let item: AudioItem

    @Environment(\.dismiss) private var dismiss
    @StateObject private var playback = AudioPlaybackManager()

    private var storedURL: URL {
        AudioStorage.shared.urlForStoredFile(relativePath: item.storedRelativePath)
    }

    var body: some View {
        VStack {
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
                    .padding(.horizontal, 10)

                HStack(spacing: 12) {
                    Button {
                        playback.togglePlay(url: storedURL)
                    } label: {
                        Label(playback.isPlaying ? "Pause" : "Play",
                              systemImage: playback.isPlaying ? "pause.fill" : "play.fill")
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

                    // ✅ Repeat icon only (no stepper / +/-)
                    Button {
                        playback.cycleLoopCount()
                    } label: {
                        ZStack(alignment: .bottomTrailing) {
                            Image(systemName: "repeat")
                                .font(.title3)
                                .padding(10)

                            // Small ×N badge (still just the repeat icon control)
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
                }

                Button("Close") { dismiss() }
                    .buttonStyle(.bordered)
                    .padding(.top, 6)
            }
            .padding(24)
            .frame(maxWidth: 520)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // Preload (no autoplay). If missing, an error message appears.
            playback.loadIfNeeded(url: storedURL)
        }
    }
}

#Preview {
    AudioEditView(item: AudioItem(
        scriptName: "MyScript01",
        originalFileName: "example_long_long_long.mp3",
        storedFileName: "example.mp3",
        storedRelativePath: "example.mp3"
    ))
}
