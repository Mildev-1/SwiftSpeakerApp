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

    @State private var editingItem: AudioItem? = nil
    @State private var practicingItem: AudioItem? = nil

    @State private var pendingDeleteItem: AudioItem? = nil

    private var mp3Type: UTType {
        UTType(filenameExtension: "mp3") ?? .audio
    }

    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 12) {
                    header

                    List {
                        ForEach(library.items) { item in
                            AudioGridRowView(
                                scriptName: item.scriptName,
                                onEditTapped: {
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        practicingItem = nil
                                        editingItem = item
                                    }
                                },
                                onPracticeTapped: {
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        editingItem = nil
                                        practicingItem = item
                                    }
                                }
                            )
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    pendingDeleteItem = item
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
                .padding(.top, 8)

                if let item = editingItem {
                    AudioEditView(
                        item: item,
                        onClose: {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                editingItem = nil
                            }
                        }
                    )
                    .transition(.move(edge: .leading))
                    .zIndex(10)
                }

                if let item = practicingItem {
                    PracticeView(
                        item: item,
                        onClose: {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                practicingItem = nil
                            }
                        }
                    )
                    .transition(.move(edge: .trailing))
                    .zIndex(11)
                }
            }
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
                            do {
                                try library.importAndAdd(sourceURL: url, scriptName: name)
                                pendingURL = nil
                                pendingSuggestedName = ""
                                isShowingTitleSheet = false
                            } catch {
                                alertMessage = error.localizedDescription
                                showAlert = true
                            }
                        }
                    )
                }
            }
            .alert("Cannot Add File", isPresented: $showAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
            .alert(
                "Remove this audio?",
                isPresented: Binding(
                    get: { pendingDeleteItem != nil },
                    set: { if !$0 { pendingDeleteItem = nil } }
                )
            ) {
                Button("Cancel", role: .cancel) {
                    pendingDeleteItem = nil
                }
                Button("Delete", role: .destructive) {
                    guard let item = pendingDeleteItem else { return }

                    if editingItem?.id == item.id {
                        withAnimation(.easeInOut(duration: 0.25)) { editingItem = nil }
                    }
                    if practicingItem?.id == item.id {
                        withAnimation(.easeInOut(duration: 0.25)) { practicingItem = nil }
                    }

                    library.deleteItem(id: item.id)
                    pendingDeleteItem = nil
                }
            } message: {
                Text("This will delete the internal audio file copy and its transcription data. This cannot be undone.")
            }
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
