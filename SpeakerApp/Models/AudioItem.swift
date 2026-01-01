//
//  AudioItem.swift
//  SpeakerApp
//
//  Stores scriptName (shown in grid) and the copied file location (internal storage).
//

import Foundation

struct AudioItem: Identifiable, Hashable, Codable {
    let id: UUID

    /// Shown in the grid, e.g. "MyScript01"
    var scriptName: String

    /// Original filename the user picked, preserved for later edit processing
    let originalFileName: String

    /// The filename actually stored in app internal storage (usually same as originalFileName)
    let storedFileName: String

    /// Relative path under AudioFiles folder (we persist this; absolute paths can change)
    let storedRelativePath: String

    init(
        id: UUID = UUID(),
        scriptName: String,
        originalFileName: String,
        storedFileName: String,
        storedRelativePath: String
    ) {
        self.id = id
        self.scriptName = scriptName
        self.originalFileName = originalFileName
        self.storedFileName = storedFileName
        self.storedRelativePath = storedRelativePath
    }
}
