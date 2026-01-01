//
//  AudioGridRowView.swift
//  SpeakerApp
//

import SwiftUI

struct AudioGridRowView: View {
    @Binding var scriptName: String
    let onEditTapped: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            TextField("MyScript01", text: $scriptName)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)

            Button("Edit") {
                onEditTapped()
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
