import SwiftUI

struct PlaybackScreenView: View {
    let item: AudioItem
    @ObservedObject var playback: AudioPlaybackManager
    @ObservedObject var transcriptVM: TranscriptViewModel

    /// Controls the fullScreenCover presentation
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
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
                if playing == false {
                    isPresented = false
                }
            }
        }
    }
}
