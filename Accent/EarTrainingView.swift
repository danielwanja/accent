import SwiftUI
import SwiftData

/// Minimal-pair tap test (PLAN.md §5.2): discrimination precedes production.
/// A native voice says one word of a pair; the user taps which one they
/// heard. Rounds weight toward the profile's weakest issues.
struct EarTrainingView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TakeRecord.date, order: .reverse) private var takes: [TakeRecord]
    @State private var coach = AudioCoach()

    struct Round {
        let issue: Issue
        let options: (String, String)
        let spoken: Int          // 0 or 1
    }

    private let roundCount = 10
    @State private var rounds: [Round] = []
    @State private var current = 0
    @State private var answered: Int?
    @State private var correct = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer()
            if rounds.isEmpty {
                EmptyView()
            } else if current >= rounds.count {
                summary
            } else {
                round(rounds[current])
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paper)
        .onAppear(perform: begin)
        .onDisappear { coach.stopAll() }
    }

    private var header: some View {
        HStack {
            Text("ACCENT")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .kerning(3)
                .foregroundStyle(Theme.muted)
            Spacer()
            Text(current < rounds.count ? "EAR TRAINING · \(current + 1)/\(rounds.count)" : "EAR TRAINING")
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .kerning(1.5)
                .foregroundStyle(Theme.muted)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close ear training")
        }
        .padding(.leading, 28)
        .padding(.trailing, 12)
        .padding(.top, 24)
    }

    private func round(_ round: Round) -> some View {
        VStack(spacing: 28) {
            Text("Which word did you hear?")
                .font(.system(size: 24, weight: .regular, design: .serif))
                .foregroundStyle(Theme.ink)
            Text(round.issue.name + "  " + round.issue.phonemes)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .kerning(1)
                .foregroundStyle(Theme.muted)
            HStack(spacing: 16) {
                optionButton(round, index: 0)
                optionButton(round, index: 1)
            }
            .padding(.horizontal, 28)
            Button {
                speak(round)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11, weight: .medium))
                    Text("REPLAY")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .kerning(1)
                }
                .foregroundStyle(Theme.muted)
                .padding(8)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }

    private func optionButton(_ round: Round, index: Int) -> some View {
        let word = index == 0 ? round.options.0 : round.options.1
        let state: (Color, Color) = {
            guard let answered else { return (Theme.ink, Theme.line) }       // unanswered
            if index == round.spoken { return (Theme.paper, Theme.ink) }    // reveal the truth
            if index == answered { return (Theme.accent, Theme.accent) }    // wrong pick
            return (Theme.upcoming, Theme.line)
        }()
        return Button {
            answer(index)
        } label: {
            Text(word)
                .font(.system(size: 26, weight: .regular, design: .serif))
                .foregroundStyle(state.0)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(answered != nil && index == round.spoken ? Theme.ink : Theme.paper))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(state.1, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .disabled(answered != nil)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("\(correct) of \(rounds.count)")
                .font(.system(size: 44, weight: .regular, design: .serif))
                .foregroundStyle(Theme.ink)
            Text(correct >= 9
                 ? "Your ear is ahead of your mouth — exactly where it should be."
                 : correct >= 7
                 ? "Solid. The pairs you missed are the sounds to drill next."
                 : "These contrasts are still blending together — hearing them is the first step to saying them.")
                .font(.system(size: 15, design: .serif))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                dismiss()
            } label: {
                Text("DONE")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .kerning(1)
                    .foregroundStyle(Theme.paper)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Theme.ink))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Session logic

    private func begin() {
        guard rounds.isEmpty else { return }
        let stats = IssueProfile.stats(from: takes)
        let trainable = Phonics.earTrainableIssues
        // Weight: 1 + misses for issues with data; uniform otherwise.
        var pool: [Issue] = []
        for issue in trainable {
            let weight = 1 + (stats.first { $0.issue.id == issue.id }?.misses ?? 0)
            pool.append(contentsOf: Array(repeating: issue, count: min(weight, 8)))
        }
        guard !pool.isEmpty else { return }
        rounds = (0..<roundCount).map { _ in
            let issue = pool.randomElement()!
            let pair = Phonics.earPairs(for: issue).randomElement()!
            return Round(issue: issue, options: pair, spoken: Bool.random() ? 0 : 1)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { speakCurrent() }
    }

    private func speakCurrent() {
        guard current < rounds.count else { return }
        speak(rounds[current])
    }

    private func speak(_ round: Round) {
        coach.speakReference(round.spoken == 0 ? round.options.0 : round.options.1)
    }

    private func answer(_ index: Int) {
        guard answered == nil, current < rounds.count else { return }
        answered = index
        if index == rounds[current].spoken {
            correct += 1
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            answered = nil
            current += 1
            speakCurrent()
        }
    }
}
