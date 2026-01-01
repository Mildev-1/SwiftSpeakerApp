//
//  AudioPlaybackManager.swift
//  SpeakerApp
//
//  Playback + repeat cycling (1...50) using a repeat icon button.
//

import Foundation
import AVFoundation
import Combine

@MainActor
final class AudioPlaybackManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isLoaded: Bool = false
    @Published private(set) var isPlaying: Bool = false

    // ✅ UI uses only repeat icon; loops are cycled by tapping it (1...50 hard limit)
    @Published private(set) var loopCount: Int = 1

    @Published var errorMessage: String? = nil

    private var player: AVAudioPlayer?
    private var loadedURL: URL?

    func loadIfNeeded(url: URL) {
        if loadedURL == url, player != nil { return }
        do {
            try load(url: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func load(url: URL) throws {
        errorMessage = nil

        guard FileManager.default.fileExists(atPath: url.path) else {
            isLoaded = false
            isPlaying = false
            player = nil
            loadedURL = nil
            errorMessage = "Stored audio file not found:\n\(url.lastPathComponent)"
            return
        }

        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif

        let p = try AVAudioPlayer(contentsOf: url)
        p.delegate = self
        p.prepareToPlay()

        player = p
        loadedURL = url
        isLoaded = true
        isPlaying = false

        applyLoopCount()
    }

    private func applyLoopCount() {
        // AVAudioPlayer.numberOfLoops: 0 = once, 1 = twice...
        let clamped = min(max(loopCount, 1), 50)
        loopCount = clamped // safe: this setter does NOT recurse anymore
        player?.numberOfLoops = clamped - 1
    }

    // ✅ Repeat icon action: cycles 1 → 2 → ... → 50 → 1
    func cycleLoopCount() {
        let next = (loopCount >= 50) ? 1 : (loopCount + 1)
        loopCount = next
        applyLoopCount()
    }

    func togglePlay(url: URL) {
        // Ensure loaded
        loadIfNeeded(url: url)
        guard let p = player, isLoaded else { return }

        if p.isPlaying {
            p.pause()
            isPlaying = false
        } else {
            p.play()
            isPlaying = true
        }
    }

    func stop() {
        guard let p = player else { return }
        p.stop()
        p.currentTime = 0
        isPlaying = false
    }

    // MARK: AVAudioPlayerDelegate
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
        }
    }
}
