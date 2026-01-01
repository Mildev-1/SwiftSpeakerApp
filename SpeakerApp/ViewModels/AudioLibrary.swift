//
//  AudioLibrary.swift
//  SpeakerApp
//

import Foundation
import Combine

@MainActor
final class AudioLibrary: ObservableObject {
    @Published private(set) var items: [AudioItem] = []

    private let store = AudioLibraryStore.shared
    private let storage = AudioStorage.shared
    private let transcriptStore = TranscriptStore.shared

    init() {
        loadFromDisk()
    }

    func loadFromDisk() {
        do {
            let loaded = try store.load()
            // prune entries if the stored file is missing
            let pruned = loaded.filter { item in
                let url = storage.urlForStoredFile(relativePath: item.storedRelativePath)
                return FileManager.default.fileExists(atPath: url.path)
            }
            items = pruned

            // ✅ keep persisted DB consistent with prune result
            if pruned.count != loaded.count {
                try? store.save(pruned)
            }
        } catch {
            items = []
        }
    }

    func nextSuggestedScriptName() -> String {
        let prefix = "MyScript"

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
        let formatted = next < 100 ? String(format: "%02d", next) : "\(next)"
        return "\(prefix)\(formatted)"
    }

    func importAndAdd(sourceURL: URL, scriptName: String) throws {
        let trimmed = scriptName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalScriptName = trimmed.isEmpty ? nextSuggestedScriptName() : trimmed

        let originalName = sourceURL.lastPathComponent
        let copyResult = try storage.copyImportedMP3ToInternalStorage(sourceURL: sourceURL)

        let item = AudioItem(
            scriptName: finalScriptName,
            originalFileName: originalName,
            storedFileName: copyResult.storedFileName,
            storedRelativePath: copyResult.relativePath
        )

        items.append(item)
        try store.save(items)
    }

    func updateScriptName(id: UUID, name: String) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].scriptName = name
        do { try store.save(items) } catch { }
    }

    /// ✅ Deletes row + internal audio + transcript + persists DB.
    func deleteItem(id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items[idx]

        // 1) Remove internal stored audio file
        try? storage.deleteStoredFile(relativePath: item.storedRelativePath)

        // 2) Remove transcript record
        transcriptStore.delete(itemID: item.id)

        // 3) Remove from list + persist
        items.remove(at: idx)
        try? store.save(items)
    }
}
