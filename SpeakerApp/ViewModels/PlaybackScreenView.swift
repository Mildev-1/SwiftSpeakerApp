import SwiftUI

struct PlaybackScreenView: View {
    let item: AudioItem
    @ObservedObject var playback: AudioPlaybackManager
    @ObservedObject var transcriptVM: TranscriptViewModel
    @Binding var isPresented: Bool

    private var fontScale: Double {
        transcriptVM.playbackSettings.clamped().playbackFontScale
    }

    private var isFlaggedMode: Bool {
        transcriptVM.playbackSettings.clamped().flaggedOnly
    }

    private var modeText: String { isFlaggedMode ? "Mode: Flagged" : "Mode: All" }
    private var modeIcon: String { isFlaggedMode ? "flag.fill" : "list.bullet" }
    private var modeColor: Color { isFlaggedMode ? .orange : .blue }

    private var baseBodySize: Double {
        #if os(iOS)
        return 17.0
        #else
        return 15.0
        #endif
    }

    private var textFont: Font { .system(size: baseBodySize * fontScale) }
    private var indexFont: Font { .system(size: max(11.0, (baseBodySize * fontScale) * 0.80)) }

    private var modeBadge: some View {
        HStack(spacing: 6) {
            Text(modeText).font(.caption).fontWeight(.semibold)
            Image(systemName: modeIcon).font(.caption).fontWeight(.semibold)
        }
        .foregroundStyle(modeColor)
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(modeColor.opacity(0.18))
        .clipShape(Capsule())
    }

    private var pauseIconName: String {
        playback.isPaused ? "play.fill" : "pause.fill"
    }

    var body: some View {
        NavigationStack {
            PlaybackTranscriptList(
                playback: playback,
                transcriptVM: transcriptVM,
                textFont: textFont,
                indexFont: indexFont
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Back
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { isPresented = false } label: {
                        Image(systemName: "chevron.left")
                    }
                }

                // Mode badge (top bar center)
                ToolbarItem(placement: .principal) {
                    modeBadge
                }

                // Pause + Stop
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 10) {
                        Button { playback.togglePause() } label: {
                            Image(systemName: pauseIconName)
                        }
                        .disabled(!playback.isPartialPlaying && !playback.isPlaying && !playback.isPaused)

                        Button {
                            playback.stop()
                            isPresented = false
                        } label: {
                            Image(systemName: "stop.fill")
                        }
                    }
                }
            }
            .onChange(of: playback.isPartialPlaying) { playing in
                if playing == false { isPresented = false }
            }
        }
    }
}

// MARK: - Split subviews (keeps compiler happy)

private struct PlaybackTranscriptList: View {
    @ObservedObject var playback: AudioPlaybackManager
    @ObservedObject var transcriptVM: TranscriptViewModel

    let textFont: Font
    let indexFont: Font

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if transcriptVM.sentenceChunks.isEmpty {
                        Text("No transcript yet.")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                            .font(textFont)
                    } else {
                        ForEach(Array(transcriptVM.sentenceChunks.enumerated()), id: \.element.id) { idx, chunk in
                            PlaybackSentenceRow(
                                index: idx + 1,
                                sentenceID: chunk.id,
                                text: transcriptVM.displayText(for: chunk),
                                isActive: playback.currentSentenceID == chunk.id,
                                textFont: textFont,
                                indexFont: indexFont
                            )
                        }
                    }
                }
                .padding(16)
            }
            .onChange(of: playback.currentSentenceID) { newID in
                guard let id = newID else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(id, anchor: .top)
                    }
                }
            }
        }
    }
}

private struct PlaybackSentenceRow: View {
    let index: Int
    let sentenceID: String
    let text: String
    let isActive: Bool
    let textFont: Font
    let indexFont: Font

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index).")
                .font(indexFont)
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)

            Text(text)
                .font(textFont)
                .foregroundStyle(isActive ? .orange : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isActive ? Color.orange.opacity(0.12) : Color.clear)
        )
        .id(sentenceID)
    }
}
