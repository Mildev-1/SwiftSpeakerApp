import Foundation
import AVFoundation

enum AudioChunkExporter {
    struct Chunk {
        let url: URL
        let startOffset: Double
        let duration: Double
    }

    enum ExportError: LocalizedError {
        case invalidDuration
        case noAudioTrack
        case cannotCreateExport
        case exportFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidDuration:
                return "Audio duration could not be determined."
            case .noAudioTrack:
                return "No audio track found in file."
            case .cannotCreateExport:
                return "Cannot create audio export session."
            case .exportFailed(let msg):
                return "Audio export failed: \(msg)"
            }
        }
    }

    /// ✅ Reliable chunking: builds an AVMutableComposition per chunk (does not rely on export.timeRange)
    static func exportM4AChunks(sourceURL: URL, chunkSeconds: Double = 55.0) async throws -> [Chunk] {
        let asset = AVURLAsset(url: sourceURL)

        // Load duration reliably
        let durationTime: CMTime
        if #available(iOS 15.0, *) {
            durationTime = try await asset.load(.duration)
        } else {
            durationTime = asset.duration
        }

        let totalSeconds = durationTime.seconds
        guard totalSeconds.isFinite, totalSeconds > 0 else {
            throw ExportError.invalidDuration
        }

        // Load audio tracks
        let audioTracks: [AVAssetTrack]
        if #available(iOS 15.0, *) {
            audioTracks = try await asset.loadTracks(withMediaType: .audio)
        } else {
            audioTracks = asset.tracks(withMediaType: .audio)
        }

        guard let sourceTrack = audioTracks.first else {
            throw ExportError.noAudioTrack
        }

        var chunks: [Chunk] = []
        var start: Double = 0

        while start < totalSeconds {
            let dur = min(chunkSeconds, totalSeconds - start)

            // Build composition with only this slice
            let composition = AVMutableComposition()
            guard
                let compTrack = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                )
            else {
                throw ExportError.noAudioTrack
            }

            let startTime = CMTime(seconds: start, preferredTimescale: 600)
            let sliceDuration = CMTime(seconds: dur, preferredTimescale: 600)
            let sliceRange = CMTimeRange(start: startTime, duration: sliceDuration)

            do {
                try compTrack.insertTimeRange(sliceRange, of: sourceTrack, at: .zero)
            } catch {
                throw ExportError.exportFailed("insertTimeRange failed: \(error.localizedDescription)")
            }

            // Export composition to M4A
            guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
                throw ExportError.cannotCreateExport
            }

            let outURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("chunk_\(UUID().uuidString)")
                .appendingPathExtension("m4a")

            export.outputURL = outURL
            export.outputFileType = .m4a
            export.shouldOptimizeForNetworkUse = false

            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                export.exportAsynchronously {
                    switch export.status {
                    case .completed:
                        cont.resume()
                    case .failed:
                        cont.resume(throwing: ExportError.exportFailed(export.error?.localizedDescription ?? "unknown"))
                    case .cancelled:
                        cont.resume(throwing: ExportError.exportFailed("cancelled"))
                    default:
                        cont.resume(throwing: ExportError.exportFailed("status=\(export.status)"))
                    }
                }
            }

            chunks.append(Chunk(url: outURL, startOffset: start, duration: dur))
            start += dur
        }

        return chunks
    }
}
