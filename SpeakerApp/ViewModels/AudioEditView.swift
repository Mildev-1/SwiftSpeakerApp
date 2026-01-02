import SwiftUI
#if os(macOS)
import AppKit
#endif

/// MODIFIED FILE: AudioEditView.swift
///
/// Now focused only on transcript display/edit and (re)transcription controls.
/// All playback/practice UI moved to PracticeView.
struct AudioEditView: View {
    let item: AudioItem
    let onClose: () -> Void

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

    private var transcriptSection: some View {
        VStack(spacing: 10) {
            // Transcript list
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

            // Transcribe / Re-Transcribe + language dropdown + status/errors
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
                        Text("Ukrainian").tag("uk")
                        Text("Russian").tag("ru")
                    }
                    .pickerStyle(.menu)
                }
                .onChange(of: transcriptVM.preferredLanguageCode) { _ in
                    // Keep behavior consistent with existing persistence expectations
                    transcriptVM.saveCutPlan(itemID: item.id)
                }

                HStack {
                    Button {
                        // Use Swift.Task to avoid custom Task symbol collision
                        _Concurrency.Task {
                            let force = transcriptVM.hasCachedTranscript
                            await transcriptVM.transcribeFromMP3(
                                itemID: item.id,
                                mp3URL: storedMP3URL,
                                languageCode: transcriptVM.preferredLanguageCode,
                                model: "base",
                                force: force
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
