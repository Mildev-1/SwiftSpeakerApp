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

            // ✅ Best-effort: sync languageCode from transcript files (for existing items),
            // then persist back so grid can show flags without re-reading transcript every time.
            var synced = pruned
            var didChange = false

            for i in synced.indices {
                if synced[i].languageCode == nil {
                    if let rec = try? transcriptStore.load(itemID: synced[i].id),
                       let lang = rec.languageCode,
                       !lang.isEmpty {
                        synced[i].languageCode = lang
                        didChange = true
                    }
                }
            }

            items = synced

            // ✅ keep persisted DB consistent with prune result + language sync
            if pruned.count != loaded.count || didChange {
                try? store.save(synced)
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
            storedRelativePath: copyResult.relativePath,
            voiceName: nil,
            languageCode: nil
        )

        items.append(item)
        try store.save(items)
    }

    func updateScriptName(id: UUID, name: String) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].scriptName = name
        do { try store.save(items) } catch { }
    }

    func updateVoiceName(id: UUID, voiceName: String) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = voiceName.trimmingCharacters(in: .whitespacesAndNewlines)
        items[idx].voiceName = trimmed.isEmpty ? nil : trimmed
        do { try store.save(items) } catch { }
    }

    func updateLanguageCode(id: UUID, languageCode: String?) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = languageCode?.trimmingCharacters(in: .whitespacesAndNewlines)
        items[idx].languageCode = (trimmed?.isEmpty == true) ? nil : trimmed
        do { try store.save(items) } catch { }
    }

    /// ✅ Deletes row + internal audio + transcript + persists DB.
    func deleteItem(id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items[idx]

        try? storage.deleteStoredFile(relativePath: item.storedRelativePath)
        transcriptStore.delete(itemID: item.id)

        items.remove(at: idx)
        do { try store.save(items) } catch { }
    }

    // MARK: - Reordering (if you already added this earlier, keep yours)

    func moveItems(from source: IndexSet, to destination: Int) {
        items.reorder(from: source, to: destination)
        do { try store.save(items) } catch { }
    }
}

private extension Array {
    mutating func reorder(from source: IndexSet, to destination: Int) {
        let moving = source.map { self[$0] }
        for i in source.sorted(by: >) { remove(at: i) }

        var dest = destination
        let removedBeforeDestination = source.filter { $0 < destination }.count
        dest -= removedBeforeDestination

        dest = Swift.max(0, Swift.min(dest, count))
        insert(contentsOf: moving, at: dest)
    }
}
