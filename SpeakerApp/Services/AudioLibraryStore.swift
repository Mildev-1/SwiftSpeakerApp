//
//  AudioLibraryStore.swift
//  SpeakerApp
//
//  Persists AudioItem list as JSON inside Application Support/SpeakerApp/audio_library.json
//

import Foundation

final class AudioLibraryStore {
    static let shared = AudioLibraryStore()
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
                return "Failed to read library data: \(msg)"
            case .writeFailed(let msg):
                return "Failed to save library data: \(msg)"
            }
        }
    }

    private func storeURL() throws -> URL {
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw StoreError.cannotAccessAppSupport
        }

        let appFolder = appSupport.appendingPathComponent("SpeakerApp", isDirectory: true)
        try fm.createDirectory(at: appFolder, withIntermediateDirectories: true)

        return appFolder.appendingPathComponent("audio_library.json", isDirectory: false)
    }

    func load() throws -> [AudioItem] {
        let url = try storeURL()
        let fm = FileManager.default

        guard fm.fileExists(atPath: url.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([AudioItem].self, from: data)
        } catch {
            throw StoreError.readFailed(error.localizedDescription)
        }
    }

    func save(_ items: [AudioItem]) throws {
        let url = try storeURL()
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: url, options: [.atomic])
        } catch {
            throw StoreError.writeFailed(error.localizedDescription)
        }
    }
}
