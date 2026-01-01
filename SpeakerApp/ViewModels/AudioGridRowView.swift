//
//  AudioGridRowView.swift
//  SpeakerApp
//
//  A single row rendered into a 2-column LazyVGrid.
//  Uses Group to emit two "cells": Title + Edit button.
//

import SwiftUI

struct AudioGridRowView: View {
    let title: String
    let onEditTapped: () -> Void

    var body: some View {
        Group {
            Text(title)
                .lineLimit(1)
                .truncationMode(.tail)

            Button {
                onEditTapped()
            } label: {
                Text("Edit")
            }
            .buttonStyle(.bordered)
            .disabled(true) // mock for now
        }
    }
}
