//
//  ContentView.swift
//  SpeakerApp
//
//  Created by Mil Moc on 01/01/2026.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var library: AudioLibrary

    @State private var isShowingImporter = false
    @State private var pendingURL: URL? = nil
    @State private var pendingSuggestedName: String = ""
    @State private var isShowingTitleSheet = false

    @State private var showAlert = false
    @State private var alertMessage = ""

    private var mp3Type: UTType {
        UTType(filenameExtension: "mp3") ?? .audio
    }

    var body: some View {
        VStack(spacing: 12) {
            header

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(library.items) { item in
                        AudioGridRowView(
                            scriptName: bindingForScriptName(itemID: item.id),
                            onEditTapped: {
                                // Mock for now (later you can use item.url / item.sourceFileName)
                            }
                        )
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding(.top, 8)
        .fileImporter(
            isPresented: $isShowingImporter,
            allowedContentTypes: [mp3Type],
            allowsMultipleSelection: false
        ) { result in
            handleImporterResult(result)
        }
        .sheet(isPresented: $isShowingTitleSheet) {
            if let url = pendingURL {
                TitleAudioSheet(
                    fileURL: url,
                    suggestedName: pendingSuggestedName,
                    onCancel: {
                        pendingURL = nil
                        pendingSuggestedName = ""
                        isShowingTitleSheet = false
                    },
                    onSave: { name in
                        library.addAudio(url: url, scriptName: name)
                        pendingURL = nil
                        pendingSuggestedName = ""
                        isShowingTitleSheet = false
                    }
                )
            }
        }
        .alert("Cannot Add File", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    private var header: some View {
        HStack {
            Text("Audio Library")
                .font(.title2)
                .fontWeight(.semibold)

            Spacer()

            Button {
                isShowingImporter = true
            } label: {
                Image(systemName: "plus")
                    .font(.title3)
                    .padding(8)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Add MP3")
        }
        .padding(.horizontal)
    }

    private func bindingForScriptName(itemID: UUID) -> Binding<String> {
        Binding(
            get: {
                library.items.first(where: { $0.id == itemID })?.scriptName ?? ""
            },
            set: { newValue in
                library.updateScriptName(id: itemID, name: newValue)
            }
        )
    }

    private func handleImporterResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            guard url.pathExtension.lowercased() == "mp3" else {
                alertMessage = "Please choose an .mp3 file."
                showAlert = true
                return
            }

            pendingURL = url
            pendingSuggestedName = library.nextSuggestedScriptName()
            isShowingTitleSheet = true

        case .failure(let error):
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AudioLibrary())
}
