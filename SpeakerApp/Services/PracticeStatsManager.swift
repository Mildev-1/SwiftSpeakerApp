import Foundation
import SwiftUI
import Combine

@MainActor
final class PracticeStatsManager: ObservableObject {
    @Published private(set) var totalSeconds: Double = 0
    @Published private(set) var logs: [PracticeSessionLog] = []

    private let store = PracticeStatsStore.shared
    private let itemID: UUID
    private let itemTitle: String

    private var pending: PendingMetadata?
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
        Task { await refresh() }
    }

    //func refresh() async {
    //    let total = await store.totalSeconds(for: itemID)
    //    let l = await store.logs(for: itemID).sorted { $0.startedAt < $1.startedAt }
     //   self.totalSeconds = total
    //    self.logs = l
   // }
    
    @MainActor
    func refresh() async {
        let total = await store.totalSeconds(for: itemID)
        let l = await store.logs(for: itemID).sorted { $0.startedAt < $1.startedAt }
        self.totalSeconds = total
        self.logs = l
    }

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

    func handlePlaybackRunningChanged(isRunning: Bool) {
        if isRunning {
            guard runningStart == nil else { return }
            guard let p = pending else { return } // only sessions initiated from our Start button
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
        guard dur >= 0.3 else { return }

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
            await refresh()
        }
    }

    /// ✅ H:MM:SS
    func formattedTotalHMS() -> String {
        Self.formatHMS(totalSeconds)
    }

    static func formatHMS(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        return String(format: "%d:%02d:%02d", h, m, sec)
    }
}
