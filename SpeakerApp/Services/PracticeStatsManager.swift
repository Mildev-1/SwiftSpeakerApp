import Foundation
import SwiftUI
import Combine

@MainActor
final class PracticeStatsManager: ObservableObject {
    @Published private(set) var totalSeconds: Double = 0

    private let store = PracticeStatsStore.shared
    private let itemID: UUID
    private let itemTitle: String

    // Prepared metadata waiting for playback to actually start
    private var pending: PendingMetadata?

    // Running session
    private var runningStart: Date?
    private var runningMeta: PendingMetadata?

    struct PendingMetadata {
        let mode: PracticeMode
        let flaggedOnly: Bool
        let wordRepeats: Int
        let sentenceRepeats: Int
    }

    init(itemID: UUID, itemTitle: String) {
        self.itemID = itemID
        self.itemTitle = itemTitle
        Task { await refreshTotal() }
    }

    func refreshTotal() async {
        let total = await store.totalSeconds(for: itemID)
        self.totalSeconds = total
    }

    /// Call right BEFORE you trigger playback start (only when starting).
    func prepareNextSession(
        mode: PracticeMode,
        flaggedOnly: Bool,
        wordRepeats: Int,
        sentenceRepeats: Int
    ) {
        pending = .init(
            mode: mode,
            flaggedOnly: flaggedOnly,
            wordRepeats: wordRepeats,
            sentenceRepeats: sentenceRepeats
        )
    }

    /// Call from `.onChange(of: playback.isPartialPlaying)`
    func handlePlaybackRunningChanged(isRunning: Bool) {
        if isRunning {
            guard runningStart == nil else { return }
            guard let p = pending else { return } // only log sessions started from our button
            pending = nil
            runningStart = Date()
            runningMeta = p
        } else {
            finalizeIfRunning()
        }
    }

    func forceStopIfRunning() {
        finalizeIfRunning()
    }

    private func finalizeIfRunning() {
        guard let start = runningStart, let meta = runningMeta else { return }
        runningStart = nil
        runningMeta = nil

        let dur = max(0.0, Date().timeIntervalSince(start))
        guard dur >= 0.3 else { return } // ignore accidental taps

        let entry = PracticeSessionLog(
            id: UUID(),
            itemID: itemID,
            itemTitle: itemTitle,
            startedAt: start,
            durationSeconds: dur,
            mode: meta.mode,
            flaggedOnly: meta.flaggedOnly,
            wordRepeats: meta.wordRepeats,
            sentenceRepeats: meta.sentenceRepeats
        )

        Task {
            await store.append(entry)
            await refreshTotal()
        }
    }

    func formattedTotal() -> String {
        let s = max(0, Int(totalSeconds.rounded()))
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60

        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(sec)s" }
        return "\(sec)s"
    }
}
