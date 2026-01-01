//
//  AudioStorage.swift
//  SpeakerApp
//
//  Handles internal storage for copied audio files.
//  Copies imported mp3 into Application Support/SpeakerApp/AudioFiles
//

import Foundation

final class AudioStorage {
    static let shared = AudioStorage()
    private init() {}

    struct CopyResult {
        let storedFileName: String
        let relativePath: String
    }

    enum StorageError: LocalizedError {
        case cannotCreateAppSupport
        case cannotCreateAudioFolder
        case cannotAccessSecurityScopedResource
        case copyFailed(String)

        var errorDescription: String? {
            switch self {
            case .cannotCreateAppSupport:
                return "Cannot access Application Support directory."
            case .cannotCreateAudioFolder:
                return "Cannot create internal AudioFiles folder."
            case .cannotAccessSecurityScopedResource:
                return "Cannot access the selected file. Please try again."
            case .copyFailed(let msg):
                return "Failed to copy file: \(msg)"
            }
        }
    }

    /// Base: ~/Library/Application Support/SpeakerApp/AudioFiles
    private func audioFilesDirectory() throws -> URL {
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw StorageError.cannotCreateAppSupport
        }

        let appFolder = appSupport.appendingPathComponent("SpeakerApp", isDirectory: true)
        let audioFolder = appFolder.appendingPathComponent("AudioFiles", isDirectory: true)

        do {
            try fm.createDirectory(at: audioFolder, withIntermediateDirectories: true)
        } catch {
            throw StorageError.cannotCreateAudioFolder
        }

        return audioFolder
    }

    func urlForStoredFile(relativePath: String) -> URL {
        // relativePath is stored within AudioFiles directory
        // We rebuild absolute URL at runtime.
        let base: URL
        do {
            base = try audioFilesDirectory()
        } catch {
            // Fallback (won't exist, but avoids crashing if called early)
            base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        }
        return base.appendingPathComponent(relativePath, isDirectory: false)
    }

    /// Copies the imported MP3 into internal storage and returns the stored filename + relative path.
    func copyImportedMP3ToInternalStorage(sourceURL: URL) throws -> CopyResult {
        let fm = FileManager.default
        let destinationDir = try audioFilesDirectory()

        // Security-scoped access (important on macOS sandbox)
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess { sourceURL.stopAccessingSecurityScopedResource() }
        }
        if !didAccess {
            // In some contexts it might still work; but if it fails, treat as error.
            // If you find this too strict, we can relax it.
            throw StorageError.cannotAccessSecurityScopedResource
        }

        let originalName = sourceURL.lastPathComponent
        let destinationURL = uniqueDestinationURL(in: destinationDir, preferredFileName: originalName)

        do {
            // Copy into internal storage
            try fm.copyItem(at: sourceURL, to: destinationURL)
            return CopyResult(
                storedFileName: destinationURL.lastPathComponent,
                relativePath: destinationURL.lastPathComponent
            )
        } catch {
            throw StorageError.copyFailed(error.localizedDescription)
        }
    }

    /// Keeps original name if possible; if collision, appends " (1)", " (2)", etc.
    private func uniqueDestinationURL(in dir: URL, preferredFileName: String) -> URL {
        let fm = FileManager.default

        let base = (preferredFileName as NSString).deletingPathExtension
        let ext = (preferredFileName as NSString).pathExtension

        var candidate = dir.appendingPathComponent(preferredFileName)
        if !fm.fileExists(atPath: candidate.path) {
            return candidate
        }

        var i = 1
        while true {
            let name = ext.isEmpty ? "\(base) (\(i))" : "\(base) (\(i)).\(ext)"
            candidate = dir.appendingPathComponent(name)
            if !fm.fileExists(atPath: candidate.path) {
                return candidate
            }
            i += 1
        }
    }
}
