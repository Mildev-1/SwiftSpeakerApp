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

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 12, alignment: .leading),
        GridItem(.fixed(80), spacing: 12, alignment: .trailing)
    ]

    private var mp3Type: UTType {
        UTType(filenameExtension: "mp3") ?? .audio
    }

    var body: some View {
        VStack(spacing: 12) {
            header

            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                    Text("Name")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("")

                    Divider().gridCellColumns(2)

                    ForEach(library.items) { item in
                        AudioGridRowView(
                            title: item.scriptName,   // ✅ grid shows ONLY scriptName
                            onEditTapped: {
                                // mock for now
                                // later you can use item.url / item.sourceFileName here
                            }
                        )
                        Divider().gridCellColumns(2)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
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
            pendingSuggestedName = library.nextSuggestedScriptName() // ✅ MyScript01...
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
