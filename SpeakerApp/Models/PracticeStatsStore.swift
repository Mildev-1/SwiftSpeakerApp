import Foundation

actor PracticeStatsStore {
    static let shared = PracticeStatsStore()

    private let fileName = "practice_stats_logs.json"

    private func fileURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent("SpeakerApp", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent(fileName)
    }

    func loadAll() -> [PracticeSessionLog] {
        do {
            let url = try fileURL()
            guard FileManager.default.fileExists(atPath: url.path) else { return [] }
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([PracticeSessionLog].self, from: data)
        } catch {
            return []
        }
    }

    func append(_ entry: PracticeSessionLog) {
        var all = loadAll()
        all.append(entry)
        saveAll(all)
    }

    func totalSeconds(for itemID: UUID) -> Double {
        loadAll()
            .filter { $0.itemID == itemID }
            .reduce(0.0) { $0 + $1.durationSeconds }
    }

    private func saveAll(_ entries: [PracticeSessionLog]) {
        do {
            let url = try fileURL()
            let data = try JSONEncoder().encode(entries)
            try data.write(to: url, options: [.atomic])
        } catch {
            // non-critical
        }
    }
}
