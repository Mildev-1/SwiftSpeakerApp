import SwiftUI

struct PracticeStatsCardView: View {
    @ObservedObject var stats: PracticeStatsManager
    @State private var expanded: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            header

            if expanded {
                Divider().opacity(0.6)
                content
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
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

                Spacer()

                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30, alignment: .center)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            if stats.logs.isEmpty {
                Text("No practice sessions yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
            } else {
                ModeBreakdownChart(logs: stats.logs)
                FlaggedBreakdownChart(logs: stats.logs)
                Last7DaysChart(logs: stats.logs)
                PracticeHeatmap(logs: stats.logs)   // ✅ fixed
            }
        }
        .padding(.top, 12)
    }
}

// MARK: - Charts

private struct ModeBreakdownChart: View {
    let logs: [PracticeSessionLog]

    var body: some View {
        let totals = PracticeStatsAgg.modeTotals(logs)
        let sum = max(1.0, totals.values.reduce(0.0, +))

        return VStack(alignment: .leading, spacing: 10) {
            Text("Modes")
                .font(.headline)

            ForEach(PracticeMode.allCasesOrdered, id: \.self) { mode in
                let v = totals[mode, default: 0]
                let pct = v / sum

                HStack(spacing: 10) {
                    Text(mode.displayName)
                        .font(.subheadline)
                        .frame(width: 92, alignment: .leading)

                    GeometryReader { geo in
                        let w = max(4, geo.size.width * pct)
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(mode.color.opacity(0.75))
                            .frame(width: w, height: 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 10)

                    Text(PracticeStatsAgg.formatMinutes(v))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 54, alignment: .trailing)
                }
            }
        }
    }
}

private struct FlaggedBreakdownChart: View {
    let logs: [PracticeSessionLog]

    var body: some View {
        let (flagged, all) = PracticeStatsAgg.flaggedTotals(logs)
        let sum = max(1.0, flagged + all)

        return VStack(alignment: .leading, spacing: 10) {
            Text("Flagged Only")
                .font(.headline)

            HStack(spacing: 10) {
                Text("Flagged")
                    .font(.subheadline)
                    .frame(width: 92, alignment: .leading)

                GeometryReader { geo in
                    let w = max(4, geo.size.width * (flagged / sum))
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.orange.opacity(0.75))
                        .frame(width: w, height: 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 10)

                Text(PracticeStatsAgg.formatMinutes(flagged))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 54, alignment: .trailing)
            }

            HStack(spacing: 10) {
                Text("All")
                    .font(.subheadline)
                    .frame(width: 92, alignment: .leading)

                GeometryReader { geo in
                    let w = max(4, geo.size.width * (all / sum))
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.blue.opacity(0.55))
                        .frame(width: w, height: 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 10)

                Text(PracticeStatsAgg.formatMinutes(all))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 54, alignment: .trailing)
            }
        }
    }
}

private struct Last7DaysChart: View {
    let logs: [PracticeSessionLog]

    var body: some View {
        let days = PracticeStatsAgg.lastNDaysTotals(logs, n: 7)

        return VStack(alignment: .leading, spacing: 10) {
            Text("Last 7 days")
                .font(.headline)

            HStack(alignment: .bottom, spacing: 6) {
                let maxVal = max(1.0, days.map(\.seconds).max() ?? 1.0)

                ForEach(days, id: \.dayStart) { d in
                    VStack(spacing: 6) {
                        GeometryReader { geo in
                            let h = max(2, geo.size.height * (d.seconds / maxVal))
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.green.opacity(0.65))
                                .frame(height: h)
                                .frame(maxHeight: .infinity, alignment: .bottom)
                        }
                        .frame(height: 46)

                        Text(d.shortLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

private struct PracticeHeatmap: View {
    let logs: [PracticeSessionLog]

    var body: some View {
        let grid = PracticeStatsAgg.heatmapGrid(logs, weeks: 12)

        return VStack(alignment: .leading, spacing: 10) {
            Text("Practice heatmap")
                .font(.headline)

            // ✅ FIX: iterate weeks by index (or enumerated) so no Hashable conformance needed.
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
    }
}

// MARK: - Aggregation

private enum PracticeStatsAgg {
    static func modeTotals(_ logs: [PracticeSessionLog]) -> [PracticeMode: Double] {
        var out: [PracticeMode: Double] = [:]
        for l in logs { out[l.mode, default: 0] += l.durationSeconds }
        return out
    }

    static func flaggedTotals(_ logs: [PracticeSessionLog]) -> (flagged: Double, all: Double) {
        var flagged: Double = 0
        var all: Double = 0
        for l in logs {
            if l.flaggedOnly { flagged += l.durationSeconds }
            else { all += l.durationSeconds }
        }
        return (flagged, all)
    }

    struct DayTotal {
        let dayStart: Date
        let seconds: Double
        let shortLabel: String
        let labelLong: String
    }

    static func lastNDaysTotals(_ logs: [PracticeSessionLog], n: Int) -> [DayTotal] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        let fmtShort = DateFormatter()
        fmtShort.dateFormat = "E"

        let fmtLong = DateFormatter()
        fmtLong.dateStyle = .medium
        fmtLong.timeStyle = .none

        var byDay: [Date: Double] = [:]
        for l in logs {
            let d = cal.startOfDay(for: l.startedAt)
            byDay[d, default: 0] += l.durationSeconds
        }

        return (0..<n).reversed().map { i in
            let d = cal.date(byAdding: .day, value: -i, to: today) ?? today
            return DayTotal(
                dayStart: d,
                seconds: byDay[d, default: 0],
                shortLabel: fmtShort.string(from: d),
                labelLong: fmtLong.string(from: d)
            )
        }
    }

    struct Heatmap {
        /// weeks[weekIndex][dayIndex]
        let weeks: [[DayTotal]]
    }

    static func heatmapGrid(_ logs: [PracticeSessionLog], weeks: Int) -> Heatmap {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        let weekday = cal.component(.weekday, from: today)
        let daysFromMonday = (weekday + 5) % 7
        let startOfThisWeek = cal.date(byAdding: .day, value: -daysFromMonday, to: today) ?? today

        let totalDays = weeks * 7
        let startDay = cal.date(byAdding: .day, value: -(totalDays - 7), to: startOfThisWeek) ?? startOfThisWeek

        var byDay: [Date: Double] = [:]
        for l in logs {
            let d = cal.startOfDay(for: l.startedAt)
            byDay[d, default: 0] += l.durationSeconds
        }

        let fmtLong = DateFormatter()
        fmtLong.dateStyle = .medium
        fmtLong.timeStyle = .none

        var allDays: [DayTotal] = []
        allDays.reserveCapacity(totalDays)

        for i in 0..<totalDays {
            let d = cal.date(byAdding: .day, value: i, to: startDay) ?? startDay
            allDays.append(
                DayTotal(
                    dayStart: d,
                    seconds: byDay[d, default: 0],
                    shortLabel: "",
                    labelLong: fmtLong.string(from: d)
                )
            )
        }

        var outWeeks: [[DayTotal]] = []
        outWeeks.reserveCapacity(weeks)

        for w in 0..<weeks {
            let slice = Array(allDays[(w * 7)..<(w * 7 + 7)])
            outWeeks.append(slice)
        }

        return Heatmap(weeks: outWeeks)
    }

    static func heatColor(forSeconds seconds: Double) -> Color {
        if seconds <= 0.0 { return Color(.tertiarySystemFill) }

        let minutes = seconds / 60.0
        let opacity: Double
        if minutes < 5 { opacity = 0.18 }
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

// MARK: - PracticeMode helpers

private extension PracticeMode {
    static var allCasesOrdered: [PracticeMode] { [.words, .sentences, .mixed, .partial] }

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
