import Foundation
import AVFoundation

enum AudioTranscoder {
    enum TranscodeError: LocalizedError {
        case cannotCreateExport
        case exportFailed(String)

        var errorDescription: String? {
            switch self {
            case .cannotCreateExport: return "Cannot create audio export session."
            case .exportFailed(let msg): return "Audio export failed: \(msg)"
            }
        }
    }

    /// Converts an audio file to .m4a in the temporary directory (overwrites if exists).
    static func toM4A(sourceURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)

        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw TranscodeError.cannotCreateExport
        }

        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")

        export.outputURL = outURL
        export.outputFileType = .m4a
        export.shouldOptimizeForNetworkUse = false

        return try await withCheckedThrowingContinuation { continuation in
            export.exportAsynchronously {
                switch export.status {
                case .completed:
                    continuation.resume(returning: outURL)
                case .failed:
                    continuation.resume(throwing: TranscodeError.exportFailed(export.error?.localizedDescription ?? "unknown"))
                case .cancelled:
                    continuation.resume(throwing: TranscodeError.exportFailed("cancelled"))
                default:
                    continuation.resume(throwing: TranscodeError.exportFailed("status=\(export.status)"))
                }
            }
        }
    }
}
