//
//  AudioPlaybackManager.swift
//  SpeakerApp
//

import Foundation
import AVFoundation
import Combine

@MainActor
final class AudioPlaybackManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isLoaded: Bool = false
    @Published private(set) var isPlaying: Bool = false
    @Published var loopCount: Int = 1 {
        didSet { loopCount = min(max(loopCount, 1), 50); applyLoopCount() }
    }
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

        #if os(iOS)
        // Optional on iOS to ensure playback works even with silent switch etc.
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
        // AVAudioPlayer.numberOfLoops:
        // 0 = play once, 1 = play twice, ...
        // We want total plays = loopCount (1...50)
        let total = min(max(loopCount, 1), 50)
        player?.numberOfLoops = total - 1
    }

    func togglePlay() {
        guard let p = player else { return }
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
