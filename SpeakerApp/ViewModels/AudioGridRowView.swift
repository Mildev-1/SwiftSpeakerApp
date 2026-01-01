//
//  AudioGridRowView.swift
//  SpeakerApp
//
//  Full-width row: editable script name + Edit button.
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
            // keep mock behavior: if you want it visually enabled but not functional:
            // .disabled(true)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
