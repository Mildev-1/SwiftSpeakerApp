//
//  SpeakerAppApp.swift
//  SpeakerApp
//
//  Created by Mil Moc on 01/01/2026.
//

import SwiftUI

@main
struct SpeakerAppApp: App {
    @StateObject private var library = AudioLibrary()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
        }
    }
}

