import SwiftUI

struct PracticeStatsCardView: View {
    @ObservedObject var stats: PracticeStatsManager
    var estimatedNextSeconds: Double? = nil

    @State private var expanded: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            header

            if expanded {
                Divider().opacity(0.6)

                VStack(alignment: .leading, spacing: 14) {
                    if stats.logs.isEmpty {
                        Text("No practice sessions yet.")
                            .foregroundStyle(.secondary)
                            .padding(.top, 10)
                    } else {
                        ModeBreakdownView(logs: stats.logs)
                        PracticeHeatmapView(logs: stats.logs, weeks: 12)
                    }
                }
                .padding(.top, 12)
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(.separator).opacity(0.35), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.22), value: expanded)
    }

    private var header: some View {
        Button {
            expanded.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "clock.fill")
                    .foregroundStyle(.secondary)

                Text(stats.formattedTotalHMS())
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                if let est = estimatedNextSeconds, est > 0.5 {
                    Text("+\(PracticeStatsManager.formatHMS(est))")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.green)
                }

                Spacer()

                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Mode breakdown (no Charts; always compiles)

private struct ModeBreakdownView: View {
    let logs: [PracticeSessionLog]

    private struct Row: Identifiable {
        let id: PracticeMode
        let mode: PracticeMode
        let seconds: Double
    }

    private var rows: [Row] {
        let totals = PracticeStatsAgg.modeTotals(logs)
        let ordered: [PracticeMode] = [.words, .sentences, .mixed, .partial]
        return ordered.map { Row(id: $0, mode: $0, seconds: totals[$0, default: 0]) }
            .filter { $0.seconds > 0.1 }
    }

    private var maxSeconds: Double {
        rows.map(\.seconds).max() ?? 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Modes")
                .font(.headline)

            VStack(spacing: 10) {
                ForEach(rows) { r in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(r.mode.color)
                                .frame(width: 8, height: 8)

                            Text(r.mode.displayName)
                                .font(.subheadline)
                                .foregroundStyle(.primary)

                            Spacer()

                            Text(PracticeStatsManager.formatHMS(r.seconds))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        GeometryReader { geo in
                            let w = geo.size.width
                            let frac = CGFloat(min(1.0, r.seconds / maxSeconds))
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color(.tertiarySystemFill))
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(r.mode.color.opacity(0.35))
                                    .frame(width: max(6, w * frac))
                            }
                        }
                        .frame(height: 10)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.tertiarySystemBackground))
        )
    }
}

// MARK: - Heatmap (GitHub-style)

private struct PracticeHeatmapView: View {
    let logs: [PracticeSessionLog]
    let weeks: Int

    var body: some View {
        let grid = PracticeStatsAgg.heatmapGrid(logs, weeks: weeks)

        return VStack(alignment: .leading, spacing: 10) {
            Text("Practice heatmap")
                .font(.headline)

            // weeks[weekIndex][dayIndex]
            HStack(alignment: .top, spacing: 4) {
                ForEach(Array(grid.weeks.enumerated()), id: \.offset) { _, week in
                    VStack(spacing: 4) {
                        ForEach(week, id: \.dayStart) { day in
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(PracticeStatsAgg.heatColor(forSeconds: day.seconds))
                                .frame(width: 12, height: 12)
                                .accessibilityLabel("\(day.labelLong): \(PracticeStatsAgg.formatMinutes(day.seconds))")
                        }
                    }
                }
            }

            Text("0 = empty • <5m low • 4h+ intense")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.tertiarySystemBackground))
        )
    }
}

// MARK: - Aggregation helpers (self-contained)

private enum PracticeStatsAgg {

    static func modeTotals(_ logs: [PracticeSessionLog]) -> [PracticeMode: Double] {
        var out: [PracticeMode: Double] = [:]
        for l in logs { out[l.mode, default: 0] += l.durationSeconds }
        return out
    }

    struct DayTotal {
        let dayStart: Date
        let seconds: Double
        let shortLabel: String
        let labelLong: String
    }

    struct Heatmap {
        /// weeks[weekIndex][dayIndex]
        let weeks: [[DayTotal]]
    }

    static func heatmapGrid(_ logs: [PracticeSessionLog], weeks: Int) -> Heatmap {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        // Sum by day
        var byDay: [Date: Double] = [:]
        for l in logs {
            let d = cal.startOfDay(for: l.startedAt)
            byDay[d, default: 0] += l.durationSeconds
        }

        let fmtShort = DateFormatter()
        fmtShort.dateFormat = "E"

        let fmtLong = DateFormatter()
        fmtLong.dateStyle = .medium
        fmtLong.timeStyle = .none

        let totalDays = weeks * 7
        let start = cal.date(byAdding: .day, value: -(totalDays - 1), to: today) ?? today

        // Build linear list of days from start..today
        var days: [DayTotal] = []
        days.reserveCapacity(totalDays)

        for i in 0..<totalDays {
            let d = cal.date(byAdding: .day, value: i, to: start) ?? start
            days.append(
                DayTotal(
                    dayStart: d,
                    seconds: byDay[d, default: 0],
                    shortLabel: fmtShort.string(from: d),
                    labelLong: fmtLong.string(from: d)
                )
            )
        }

        // Chunk into weeks
        var w: [[DayTotal]] = []
        w.reserveCapacity(weeks)

        var idx = 0
        for _ in 0..<weeks {
            let slice = Array(days[idx..<min(idx+7, days.count)])
            w.append(slice)
            idx += 7
        }

        return Heatmap(weeks: w)
    }

    static func heatColor(forSeconds seconds: Double) -> Color {
        // Intensity bands: 0, <5m, <30m, <2h, <4h, >=4h
        let minutes = seconds / 60.0
        let opacity: Double
        if minutes <= 0.01 { opacity = 0.10 }
        else if minutes < 5 { opacity = 0.18 }
        else if minutes < 30 { opacity = 0.32 }
        else if minutes < 120 { opacity = 0.50 }
        else if minutes < 240 { opacity = 0.70 }
        else { opacity = 0.90 }

        return Color.green.opacity(opacity)
    }

    static func formatMinutes(_ seconds: Double) -> String {
        let m = Int((seconds / 60.0).rounded())
        if m >= 60 {
            let h = m / 60
            let r = m % 60
            return "\(h)h \(r)m"
        }
        return "\(m)m"
    }
}

// MARK: - PracticeMode helpers (safe + local)

private extension PracticeMode {
    var displayName: String {
        switch self {
        case .words: return "Words"
        case .sentences: return "Sentences"
        case .mixed: return "Mixed"
        case .partial: return "Partial"
        }
    }

    var color: Color {
        switch self {
        case .words: return .blue
        case .sentences: return .orange
        case .mixed: return .purple
        case .partial: return .gray
        }
    }
}
