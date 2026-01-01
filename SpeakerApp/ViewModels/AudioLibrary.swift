//
//  AudioLibrary.swift
//  SpeakerApp
//
//  In-memory storage for AudioItem entries.
//

import Foundation
import Combine

@MainActor
final class AudioLibrary: ObservableObject {
    @Published private(set) var items: [AudioItem] = []

    /// Suggested pattern: MyScript01, MyScript02, ...
    func nextSuggestedScriptName() -> String {
        let prefix = "MyScript"

        // Find max N in existing names that match MyScriptNN...
        var maxNumber = 0
        for item in items {
            let name = item.scriptName
            guard name.hasPrefix(prefix) else { continue }
            let suffix = String(name.dropFirst(prefix.count))
            if let n = Int(suffix) {
                maxNumber = max(maxNumber, n)
            }
        }

        let next = maxNumber + 1
        // 01..99 => 2 digits; 100+ => no truncation
        let formatted = next < 100 ? String(format: "%02d", next) : "\(next)"
        return "\(prefix)\(formatted)"
    }

    func addAudio(url: URL, scriptName: String) {
        let trimmed = scriptName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? nextSuggestedScriptName() : trimmed
        items.append(AudioItem(url: url, scriptName: finalName))
    }
}
