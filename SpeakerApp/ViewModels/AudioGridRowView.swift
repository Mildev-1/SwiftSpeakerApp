import SwiftUI

struct AudioGridRowView: View {
    let scriptName: String
    let languageCode: String?
    let onEditTapped: () -> Void
    let onPracticeTapped: () -> Void

    private var titleText: Text {
        let name = (scriptName.isEmpty ? "Untitled" : scriptName)
        if let flag = LanguageFlag.emoji(for: languageCode) {
            return Text(flag + " ") + Text(name)
        }
        return Text(name)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {

            // Multi-line title on the left
            titleText
                .font(.subheadline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Buttons on the right
            HStack(spacing: 10) {
                Button(action: onEditTapped) {
                    Image(systemName: "pencil")
                        .font(.headline)
                        .frame(width: 40, height: 34)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Edit")

                Button(action: onPracticeTapped) {
                    Image(systemName: "person.wave.2")
                        .font(.headline)
                        .frame(width: 40, height: 34)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Practice")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        )
    }
}
