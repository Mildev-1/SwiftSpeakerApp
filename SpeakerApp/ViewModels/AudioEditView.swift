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
                        playback.loadIfNeeded(url: storedURL)
                        playback.togglePlay()
                    } label: {
                        Label(playback.isPlaying ? "Pause" : "Play",
                              systemImage: playback.isPlaying ? "pause.fill" : "play.fill")
                            .frame(minWidth: 110)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!FileManager.default.fileExists(atPath: storedURL.path))

                    Button {
                        playback.stop()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                            .frame(minWidth: 90)
                    }
                    .buttonStyle(.bordered)

                }

                VStack(spacing: 8) {
                    Text("Loop: \(playback.loopCount)× (max 50)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Stepper(value: $playback.loopCount, in: 1...50) {
                        Text("Repeat")
                    }
                    .frame(maxWidth: 260)
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
            // Prepare (no autoplay) so first Play is instant
            playback.loadIfNeeded(url: storedURL)
        }
    }
}

#Preview {
    AudioEditView(item: AudioItem(
        scriptName: "MyScript01",
        originalFileName: "example_with_a_long_filename_example_with_a_long_filename.mp3",
        storedFileName: "example.mp3",
        storedRelativePath: "example.mp3"
    ))
}
