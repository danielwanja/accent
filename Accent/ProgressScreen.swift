import SwiftUI
import SwiftData
import Charts

/// Per-issue mastery and session history.
struct ProgressScreen: View {
    @Query(sort: \TakeRecord.date, order: .reverse) private var takes: [TakeRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("ACCENT")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .kerning(3)
                    .foregroundStyle(Theme.muted)
                Spacer()
                Text("PROGRESS")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .kerning(1.5)
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)

            if takes.isEmpty {
                Spacer()
                Text("No reads yet.")
                    .font(.system(size: 24, weight: .regular, design: .serif))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        masteryBars
                        cleanRateChart
                        history
                    }
                    .padding(28)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paper)
    }

    private var masteryBars: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("BY SOUND")
            if IssueProfile.stats(from: takes).isEmpty {
                Text("Sound progress appears after a take with reliable sound evidence. Recognition alone doesn't measure pronunciation.")
                    .font(.system(size: 14, design: .serif))
                    .foregroundStyle(Theme.muted)
            }
            ForEach(IssueProfile.stats(from: takes)) { stat in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(stat.issue.name)
                            .font(.system(size: 15, weight: .medium, design: .serif))
                            .foregroundStyle(Theme.ink)
                        Text(stat.issue.phonemes)
                            .font(.system(size: 12, design: .serif))
                            .foregroundStyle(Theme.muted)
                        Spacer()
                        Text("\(stat.attempts - stat.misses)/\(stat.attempts)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Theme.muted)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.line)
                            Capsule()
                                .fill(stat.mastery < 0.6 ? Theme.accent : (stat.mastery < 0.85 ? Theme.amber : Theme.ink))
                                .frame(width: max(6, geo.size.width * stat.mastery))
                        }
                    }
                    .frame(height: 6)
                }
            }
        }
    }

    private var cleanRateChart: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("WORDS UNDERSTOOD")
            Chart(Array(takes.reversed().enumerated()), id: \.offset) { index, take in
                LineMark(
                    x: .value("Read", index + 1),
                    y: .value("Understood", take.readCount == 0 ? 0 : Double(take.understoodCount) / Double(take.readCount)))
                    .foregroundStyle(Theme.accent)
                PointMark(
                    x: .value("Read", index + 1),
                    y: .value("Understood", take.readCount == 0 ? 0 : Double(take.understoodCount) / Double(take.readCount)))
                    .foregroundStyle(Theme.accent)
            }
            .chartYScale(domain: 0...1)
            .chartYAxis {
                AxisMarks(values: [0, 0.5, 1]) { value in
                    AxisGridLine().foregroundStyle(Theme.line)
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text("\(Int(v * 100))%")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Theme.muted)
                        }
                    }
                }
            }
            .chartXAxis(.hidden)
            .frame(height: 120)
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("HISTORY")
            ForEach(takes.prefix(20)) { take in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(take.passageTitle)
                            .font(.system(size: 15, weight: .medium, design: .serif))
                            .foregroundStyle(Theme.ink)
                        Text(take.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Text("\(take.understoodCount)/\(take.readCount)")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(take.understoodCount == take.readCount ? Theme.muted : Theme.accent)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .kerning(2)
            .foregroundStyle(Theme.muted)
    }
}
