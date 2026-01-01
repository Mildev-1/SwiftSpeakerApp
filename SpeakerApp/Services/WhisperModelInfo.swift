import Foundation

enum WhisperModelInfo {
    // Expected sizes (approx, based on Hugging Face repo listing)
    static func expectedBytes(for model: String) -> Int64? {
        switch model {
        case "base":
            return 147_000_000   // ~147 MB :contentReference[oaicite:4]{index=4}
        case "tiny":
            return 76_600_000    // ~76.6 MB :contentReference[oaicite:5]{index=5}
        default:
            return nil
        }
    }

    /// Root where WhisperKit stores HF models (matches your error paths)
    static func whisperKitRootDir() -> URL? {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        return docs
            .appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml", isDirectory: true)
    }

    /// Total bytes currently on disk under WhisperKit's model root (includes .cache + final folders)
    static func currentBytesOnDisk() -> Int64 {
        guard let root = whisperKitRootDir() else { return 0 }
        return directorySize(root)
    }

    private static func directorySize(_ url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            do {
                let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                if values.isRegularFile == true, let size = values.fileSize {
                    total += Int64(size)
                }
            } catch {
                continue
            }
        }
        return total
    }

    static func formatMB(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1_000_000.0
        return String(format: "%.1f MB", mb)
    }
}
