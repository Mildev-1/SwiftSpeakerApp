import Foundation

final class CutPlanStore {
    static let shared = CutPlanStore()
    private init() {}

    enum StoreError: LocalizedError {
        case cannotAccessAppSupport
        case readFailed(String)
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .cannotAccessAppSupport: return "Cannot access Application Support directory."
            case .readFailed(let msg): return "Failed to read cut plan: \(msg)"
            case .writeFailed(let msg): return "Failed to save cut plan: \(msg)"
            }
        }
    }

    private func cutsDirectory() throws -> URL {
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw StoreError.cannotAccessAppSupport
        }

        let appFolder = appSupport.appendingPathComponent("SpeakerApp", isDirectory: true)
        let cuts = appFolder.appendingPathComponent("Cuts", isDirectory: true)
        try fm.createDirectory(at: cuts, withIntermediateDirectories: true)
        return cuts
    }

    private func recordURL(for itemID: UUID) throws -> URL {
        let dir = try cutsDirectory()
        return dir.appendingPathComponent("\(itemID.uuidString).json", isDirectory: false)
    }

    func load(itemID: UUID) throws -> CutPlanRecord? {
        let url = try recordURL(for: itemID)
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return nil }

        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(CutPlanRecord.self, from: data)
        } catch {
            throw StoreError.readFailed(error.localizedDescription)
        }
    }

    func save(itemID: UUID, record: CutPlanRecord) throws {
        let url = try recordURL(for: itemID)
        do {
            let data = try JSONEncoder().encode(record)
            try data.write(to: url, options: [.atomic])
        } catch {
            throw StoreError.writeFailed(error.localizedDescription)
        }
    }

    func delete(itemID: UUID) {
        guard let url = try? recordURL(for: itemID) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
