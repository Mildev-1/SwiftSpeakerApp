import SwiftUI
#if os(macOS)
import AppKit
#endif

struct AudioEditView: View {
    let item: AudioItem
    let onClose: () -> Void

    @EnvironmentObject private var library: AudioLibrary

    @StateObject private var transcriptVM = TranscriptViewModel()
    @StateObject private var playback = AudioPlaybackManager()

    @State private var selectedChunk: SentenceChunk? = nil

    // Editable title
    @State private var titleText: String = ""
    @State private var lastSavedTitle: String = ""

    // ✅ Voice (editable)
    @State private var voiceText: String = ""
    @State private var lastSavedVoice: String = ""

    private let transcriptStore = TranscriptStore.shared

    private var storedMP3URL: URL {
        AudioStorage.shared.urlForStoredFile(relativePath: item.storedRelativePath)
    }

    /// Always read latest persisted values (languageCode / voiceName) from library if available.
    private var currentItem: AudioItem {
        library.items.first(where: { $0.id == item.id }) ?? item
    }

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                topBar

                ScrollView {
                    VStack(spacing: 18) {
                        headerSection
                        basicPlaybackSection
                        transcriptSection
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

            // Title
            titleText = currentItem.scriptName
            lastSavedTitle = currentItem.scriptName

            // Voice
            let v = (currentItem.voiceName ?? "")
            voiceText = v
            lastSavedVoice = v
        }
        .onDisappear {
            playback.stop()
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
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.bordered)

            Spacer()
            Text("Edit").font(.headline)
            Spacer()

            Rectangle().fill(.clear).frame(width: 44, height: 44)
        }
        .padding(.horizontal)
        .padding(.top, 12)
    }

    private var headerSection: some View {
        VStack(spacing: 10) {

            // ✅ Flag centered above title if available
            if let flag = LanguageFlag.emoji(for: currentItem.languageCode) {
                Text(flag)
                    .font(.system(size: 46))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 2)
            }

            // ✅ Multi-line editable title
            multilineTitleField

            // ✅ Voice label + editable field under title
            VStack(spacing: 6) {
                Text("Voice")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)

                TextField("Voice", text: $voiceText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 420)
                    .multilineTextAlignment(.center)
                    .onSubmit { persistVoiceIfNeeded() }
                    .onChange(of: voiceText) { _ in
                        persistVoiceIfNeeded()
                    }
            }
        }
    }

    @ViewBuilder
    private var multilineTitleField: some View {
        if #available(iOS 16.0, macOS 13.0, *) {
            TextField("Title", text: $titleText, axis: .vertical)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)
                .fixedSize(horizontal: false, vertical: true)
                .onSubmit { persistTitleIfNeeded() }
                .onChange(of: titleText) { _ in
                    persistTitleIfNeeded()
                }
        } else {
            TextField("Title", text: $titleText)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .textFieldStyle(.roundedBorder)
                .onSubmit { persistTitleIfNeeded() }
                .onChange(of: titleText) { _ in
                    persistTitleIfNeeded()
                }
        }
    }

    private func persistTitleIfNeeded() {
        let trimmed = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard trimmed != lastSavedTitle else { return }

        library.updateScriptName(id: item.id, name: trimmed)
        lastSavedTitle = trimmed
    }

    private func persistVoiceIfNeeded() {
        let trimmed = voiceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != lastSavedVoice else { return }

        library.updateVoiceName(id: item.id, voiceName: trimmed)
        lastSavedVoice = trimmed
    }

    // ✅ Basic Play / Stop here
    private var basicPlaybackSection: some View {
        HStack(spacing: 12) {
            Button {
                playback.togglePlay(url: storedMP3URL)
            } label: {
                Label(
                    playback.isPlaying ? "Pause" : "Play",
                    systemImage: playback.isPlaying ? "pause.fill" : "play.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!FileManager.default.fileExists(atPath: storedMP3URL.path))

            Button {
                playback.stop()
            } label: {
                Label("Stop", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!playback.isPlaying && !playback.isPartialPlaying)
        }
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        )
    }

    private var transcriptSection: some View {
        VStack(spacing: 10) {

            // Transcript list bubble
            VStack(spacing: 10) {
                if transcriptVM.sentenceChunks.isEmpty {
                    Text(transcriptVM.isTranscribing ? "Transcribing…" : "No transcript yet.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(transcriptVM.sentenceChunks.enumerated()), id: \.element.id) { _, chunk in
                            let textToShow = transcriptVM.displayText(for: chunk)

                            Button { selectedChunk = chunk } label: {
                                Text(textToShow)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .background(.thinMaterial)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(.quaternary, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                        }
                    }
                }
            }
            .padding(12)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.quaternary, lineWidth: 1)
            )

            // File name block
            VStack(spacing: 6) {
                Text("File name:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(item.originalFileName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.quaternary, lineWidth: 1)
            )

            // Transcription components bubble
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Text("Language")
                        .font(.callout)
                        .fontWeight(.semibold)
                    Spacer()

                    Picker("", selection: $transcriptVM.preferredLanguageCode) {
                        Text("Auto").tag("auto")
                        Text("English").tag("en")
                        Text("Polish").tag("pl")
                        Text("Spanish").tag("es")
                        Text("German").tag("de")
                        Text("French").tag("fr")
                        Text("Italian").tag("it")
                    }
                    .pickerStyle(.menu)
                }
                .onChange(of: transcriptVM.preferredLanguageCode) { _ in
                    transcriptVM.saveCutPlan(itemID: item.id)
                }

                HStack {
                    Button {
                        _Concurrency.Task {
                            let force = transcriptVM.hasCachedTranscript
                            await transcriptVM.transcribeFromMP3(
                                itemID: item.id,
                                mp3URL: storedMP3URL,
                                languageCode: transcriptVM.preferredLanguageCode,
                                model: "base",
                                force: force
                            )

                            // ✅ Persist detected languageCode into AudioItem after transcription
                            if let rec = try? transcriptStore.load(itemID: item.id),
                               let lang = rec.languageCode,
                               !lang.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                await MainActor.run {
                                    library.updateLanguageCode(id: item.id, languageCode: lang)
                                }
                            }
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
                        .padding(.top, 4)
                }
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
}
