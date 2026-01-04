import SwiftUI

struct AudioGridRowView: View {
    let scriptName: String
    let voiceName: String?
    let languageCode: String?

    let onEditTapped: () -> Void
    let onPracticeTapped: () -> Void

    private var titleString: String {
        scriptName.isEmpty ? "Untitled" : scriptName
    }

    private var flagEmoji: String? {
        LanguageFlag.emoji(for: languageCode)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                // Title line
                HStack(spacing: 6) {
                    if let flagEmoji {
                        Text(flagEmoji)
                    }
                    Text(titleString)
                        .foregroundStyle(Color.yellow) // ✅ yellow title
                }
                .font(.subheadline)
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

                // Voice line (if any)
                if let v = voiceName?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !v.isEmpty {
                    Text(v)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                Button(action: onEditTapped) {
                    Image(systemName: "pencil")
                        .font(.headline)
                        .frame(width: 40, height: 34)
                }
                .buttonStyle(.bordered)

                Button(action: onPracticeTapped) {
                    Image(systemName: "person.wave.2")
                        .font(.headline)
                        .frame(width: 40, height: 34)
                }
                .buttonStyle(.bordered)
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
