import Foundation

enum WhisperModelReset {
    static func resetAll() {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let hfRoot = docs.appendingPathComponent("huggingface", isDirectory: true)
        try? fm.removeItem(at: hfRoot)
    }
}
