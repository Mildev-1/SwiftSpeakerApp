//
//  AudioItem.swift
//  SpeakerApp
//
//  Stores a selected audio file URL + user title.
//

import Foundation

struct AudioItem: Identifiable, Hashable {
    let id: UUID
    let url: URL
    var title: String

    init(id: UUID = UUID(), url: URL, title: String) {
        self.id = id
        self.url = url
        self.title = title
    }
}
