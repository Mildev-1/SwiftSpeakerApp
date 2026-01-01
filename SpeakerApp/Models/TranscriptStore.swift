import Foundation

final class TranscriptStore {
    static let shared = TranscriptStore()
    private init() {}

    enum StoreError: LocalizedError {
        case cannotAccessAppSupport
        case readFailed(String)
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .cannotAccessAppSupport:
                return "Cannot access Application Support directory."
            case .readFailed(let msg):
                return "Failed to read transcript: \(msg)"
            case .writeFailed(let msg):
                return "Failed to save transcript: \(msg)"
            }
        }
    }

    private func transcriptsDirectory() throws -> URL {
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw StoreError.cannotAccessAppSupport
        }

        let appFolder = appSupport.appendingPathComponent("SpeakerApp", isDirectory: true)
        let transcripts = appFolder.appendingPathComponent("Transcripts", isDirectory: true)

        try fm.createDirectory(at: transcripts, withIntermediateDirectories: true)
        return transcripts
    }

    private func recordURL(for itemID: UUID) throws -> URL {
        let dir = try transcriptsDirectory()
        return dir.appendingPathComponent("\(itemID.uuidString).json", isDirectory: false)
    }

    func load(itemID: UUID) throws -> TranscriptRecord? {
        let url = try recordURL(for: itemID)
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return nil }

        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(TranscriptRecord.self, from: data)
        } catch {
            throw StoreError.readFailed(error.localizedDescription)
        }
    }

    func save(itemID: UUID, record: TranscriptRecord) throws {
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
