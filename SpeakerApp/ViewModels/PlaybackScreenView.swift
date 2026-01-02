import SwiftUI

struct PlaybackScreenView: View {
    let item: AudioItem
    @ObservedObject var playback: AudioPlaybackManager
    @ObservedObject var transcriptVM: TranscriptViewModel
    @Binding var isPresented: Bool

    private var fontScale: Double {
        transcriptVM.playbackSettings.clamped().playbackFontScale
    }

    private var baseBodySize: Double {
        // Keep it stable and predictable. (Dynamic type still exists for other UI.)
        #if os(iOS)
        return 17.0
        #else
        return 15.0
        #endif
    }

    private var textFont: Font {
        .system(size: baseBodySize * fontScale)
    }

    private var indexFont: Font {
        .system(size: max(11.0, (baseBodySize * fontScale) * 0.80))
    }

    var body: some View {
        NavigationStack {
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
                                let isActive = (playback.currentSentenceID == chunk.id)
                                let textToShow = transcriptVM.displayText(for: chunk)

                                HStack(alignment: .top, spacing: 10) {
                                    Text("\(idx + 1).")
                                        .font(indexFont)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 34, alignment: .trailing)

                                    Text(textToShow)
                                        .font(textFont)
                                        .foregroundStyle(isActive ? .orange : .primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(isActive ? .orange.opacity(0.12) : Color.clear)
                                )
                                .id(chunk.id)
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { isPresented = false } label: {
                        Image(systemName: "chevron.left")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        playback.stop()
                        isPresented = false
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                }
            }
            .onChange(of: playback.isPartialPlaying) { playing in
                if playing == false { isPresented = false }
            }
        }
    }
}
