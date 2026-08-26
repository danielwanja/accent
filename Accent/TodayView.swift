import SwiftUI
import SwiftData

/// The coach's front door: today's focus issue and the way into a session.
struct TodayView: View {
    @Environment(AppModel.self) private var app
    @Query(sort: \TakeRecord.date, order: .reverse) private var takes: [TakeRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("ACCENT")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .kerning(3)
                    .foregroundStyle(Theme.muted)
                Spacer()
                Text("TODAY")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .kerning(1.5)
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if takes.isEmpty {
                        onboarding
                    } else if let focus = IssueProfile.focus(from: takes) {
                        focusCard(focus)
                    } else {
                        allClear
                    }
                    if !takes.isEmpty {
                        lastTakeLine
                    }
                }
                .padding(28)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paper)
    }

    private var onboarding: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Start with a two-minute diagnostic.")
                .font(.system(size: 32, weight: .regular, design: .serif))
                .foregroundStyle(Theme.ink)
            Text("One short passage that touches every classic French-speaker issue. It seeds your profile; every session after this is built from it.")
                .font(.system(size: 15, design: .serif))
                .foregroundStyle(Theme.muted)
            actionButton("RUN DIAGNOSTIC", icon: "waveform") {
                app.startDiagnostic()
            }
        }
    }

    private func focusCard(_ stat: IssueStat) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("TODAY'S FOCUS")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .kerning(2)
                .foregroundStyle(Theme.muted)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(stat.issue.name)
                    .font(.system(size: 40, weight: .regular, design: .serif))
                    .foregroundStyle(Theme.ink)
                Text(stat.issue.phonemes)
                    .font(.system(size: 17, design: .serif))
                    .foregroundStyle(Theme.accent)
                Spacer()
                Text("\(Int(stat.mastery * 100))%")
                    .font(.system(size: 17, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.muted)
            }
            Text(stat.issue.why)
                .font(.system(size: 15, design: .serif))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(stat.issue.cue)
                .font(.system(size: 14, design: .serif))
                .italic()
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            if !stat.issue.minimalPairs.isEmpty {
                Text(stat.issue.minimalPairs.joined(separator: "   "))
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(Theme.muted)
            }
            HStack(spacing: 12) {
                actionButton(app.isGeneratingDrill ? "PREPARING…" : "PRACTICE THIS", icon: "waveform") {
                    app.startPractice(for: stat.issue)
                }
                .disabled(app.isGeneratingDrill)
                actionButton("DIAGNOSTIC", icon: "stethoscope") {
                    app.startDiagnostic()
                }
            }
        }
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
    }

    private var allClear: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Nothing flagged yet.")
                .font(.system(size: 32, weight: .regular, design: .serif))
                .foregroundStyle(Theme.ink)
            Text("Read a few more passages and your weak spots will surface here.")
                .font(.system(size: 15, design: .serif))
                .foregroundStyle(Theme.muted)
            actionButton("RUN DIAGNOSTIC", icon: "waveform") {
                app.startDiagnostic()
            }
        }
    }

    private var lastTakeLine: some View {
        Group {
            if let last = takes.first {
                Text("Last read: \(last.passageTitle) — \(last.cleanCount)/\(last.readCount) clean, \(last.date.formatted(.relative(presentation: .named)))")
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .kerning(0.5)
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    private func actionButton(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                Text(label)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .kerning(1)
                    .fixedSize()
            }
            .foregroundStyle(Theme.paper)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Capsule().fill(Theme.ink))
        }
        .buttonStyle(.plain)
    }
}
