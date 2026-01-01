//
//  AudioItem.swift
//  SpeakerApp
//
//  Stores a selected audio file URL + user script name (displayed in grid).
//

import Foundation

struct AudioItem: Identifiable, Hashable {
    let id: UUID
    let url: URL

    /// Display name shown in the grid: e.g. "MyScript01"
    var scriptName: String

    /// Real source filename for later processing (NOT shown in grid)
    var sourceFileName: String { url.lastPathComponent }

    init(id: UUID = UUID(), url: URL, scriptName: String) {
        self.id = id
        self.url = url
        self.scriptName = scriptName
    }
}
