//
//  TitleAudioSheet.swift
//  SpeakerApp
//
//  Popup sheet to set the display title for the selected mp3.
//

import SwiftUI

struct TitleAudioSheet: View {
    let fileURL: URL
    let onCancel: () -> Void
    let onSave: (String) -> Void

    @State private var title: String

    init(fileURL: URL, onCancel: @escaping () -> Void, onSave: @escaping (String) -> Void) {
        self.fileURL = fileURL
        self.onCancel = onCancel
        self.onSave = onSave

        let defaultTitle = fileURL.deletingPathExtension().lastPathComponent
        _title = State(initialValue: defaultTitle)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add Audio")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 6) {
                Text("File")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(fileURL.lastPathComponent)
                    .font(.subheadline)
                    .lineLimit(2)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Title")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("Enter title", text: $title)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                Button("Save") { onSave(title) }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.top, 6)
        }
        .padding(20)
        .frame(minWidth: 420)
    }
}

#Preview {
    TitleAudioSheet(
        fileURL: URL(fileURLWithPath: "/Users/test/Downloads/example.mp3"),
        onCancel: {},
        onSave: { _ in }
    )
}
