//
//  TitleAudioSheet.swift
//  SpeakerApp
//
//  Popup sheet to set the display script name (MyScript01...).
//  Model keeps the real file URL/filename for later edit processing.
//

import SwiftUI

struct TitleAudioSheet: View {
    let fileURL: URL
    let suggestedName: String
    let onCancel: () -> Void
    let onSave: (String) -> Void

    @State private var name: String

    init(
        fileURL: URL,
        suggestedName: String,
        onCancel: @escaping () -> Void,
        onSave: @escaping (String) -> Void
    ) {
        self.fileURL = fileURL
        self.suggestedName = suggestedName
        self.onCancel = onCancel
        self.onSave = onSave
        _name = State(initialValue: suggestedName) // ✅ default to MyScript01 pattern
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add Audio")
                .font(.title2)
                .fontWeight(.semibold)

            // Optional: show the real file name here (not in grid)
            VStack(alignment: .leading, spacing: 6) {
                Text("Selected file (stored, not shown in grid)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(fileURL.lastPathComponent)
                    .font(.subheadline)
                    .lineLimit(2)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Script name")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("MyScript01", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                Button("Save") { onSave(name) }
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
        suggestedName: "MyScript01",
        onCancel: {},
        onSave: { _ in }
    )
}
