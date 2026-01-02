import Foundation
import AVFoundation

enum AudioSnippetExporter {
    enum ExportError: LocalizedError {
        case cannotCreateExport
        case exportFailed(String)

        var errorDescription: String? {
            switch self {
            case .cannotCreateExport:
                return "Cannot create audio export session."
            case .exportFailed(let msg):
                return "Audio export failed: \(msg)"
            }
        }
    }

    static func exportFirstM4A(sourceURL: URL, seconds: Double) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)

        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw ExportError.cannotCreateExport
        }

        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("snippet-\(UUID().uuidString)")
            .appendingPathExtension("m4a")

        export.outputURL = outURL
        export.outputFileType = .m4a

        let dur = max(1.0, seconds)
        export.timeRange = CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: dur, preferredTimescale: 600)
        )

        return try await withCheckedThrowingContinuation { cont in
            export.exportAsynchronously {
                switch export.status {
                case .completed:
                    cont.resume(returning: outURL)
                case .failed:
                    cont.resume(throwing: ExportError.exportFailed(export.error?.localizedDescription ?? "unknown"))
                case .cancelled:
                    cont.resume(throwing: ExportError.exportFailed("cancelled"))
                default:
                    cont.resume(throwing: ExportError.exportFailed("status=\(export.status)"))
                }
            }
        }
    }
}
