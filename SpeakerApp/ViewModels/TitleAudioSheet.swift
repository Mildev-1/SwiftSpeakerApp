//
//  TitleAudioSheet.swift
//  SpeakerApp
//
//  Popup sheet to set the display script name (MyScript01...).
//  Adds centered layout, proper margins, and truncation for long filenames.
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
        _name = State(initialValue: suggestedName)
    }

    var body: some View {
        VStack {
            VStack(spacing: 16) {
                Text("Add Audio")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)

                VStack(spacing: 8) {
                    Text("Selected file")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Text(fileURL.lastPathComponent)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .lineLimit(4)            // ✅ 4 lines max
                        .truncationMode(.tail)   // ✅ ... at end
                        .frame(maxWidth: 420)
                }

                VStack(alignment: .center, spacing: 8) {
                    Text("Script name")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    TextField("MyScript01", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 320)         // ✅ centered field width
                }

                HStack(spacing: 12) {
                    Button("Cancel") { onCancel() }
                        .buttonStyle(.bordered)

                    Button("Save") { onSave(name) }
                        .buttonStyle(.borderedProminent)
                }
                .padding(.top, 6)
            }
            .padding(24)                              // ✅ real margins inside popup
            .frame(maxWidth: 520)                     // ✅ keeps content centered/nice
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(24)                              // ✅ outer margins (sheet edges)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }
}

#Preview {
    TitleAudioSheet(
        fileURL: URL(fileURLWithPath: "/Users/test/Downloads/this_is_a_very_long_file_name_that_should_be_cut_off_after_two_lines_and_then_show_dots.mp3"),
        suggestedName: "MyScript01",
        onCancel: {},
        onSave: { _ in }
    )
}
