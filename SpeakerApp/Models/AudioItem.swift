import Foundation

struct AudioItem: Identifiable, Codable, Hashable {
    let id: UUID

    var scriptName: String
    var originalFileName: String
    var storedFileName: String
    var storedRelativePath: String

    /// User-editable label shown in Edit screen under Title.
    /// Optional so older saved JSON loads without migration code.
    var voiceName: String?

    /// Persisted after transcription. Example: "en", "es", "pl", "de", "fr", "it", etc.
    /// Optional so older saved JSON loads without migration code.
    var languageCode: String?

    init(
        id: UUID = UUID(),
        scriptName: String,
        originalFileName: String,
        storedFileName: String,
        storedRelativePath: String,
        voiceName: String? = nil,
        languageCode: String? = nil
    ) {
        self.id = id
        self.scriptName = scriptName
        self.originalFileName = originalFileName
        self.storedFileName = storedFileName
        self.storedRelativePath = storedRelativePath
        self.voiceName = voiceName
        self.languageCode = languageCode
    }
}
