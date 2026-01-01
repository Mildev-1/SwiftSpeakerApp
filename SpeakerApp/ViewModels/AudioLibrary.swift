//
//  AudioLibrary.swift
//  SpeakerApp
//
//  In-memory storage for AudioItem entries.
//

import Foundation
import Combine   // ✅ REQUIRED for ObservableObject + @Published

@MainActor
final class AudioLibrary: ObservableObject {
    @Published private(set) var items: [AudioItem] = []

    func addAudio(url: URL, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = trimmed.isEmpty ? url.deletingPathExtension().lastPathComponent : trimmed
        items.append(AudioItem(url: url, title: finalTitle))
    }
}
