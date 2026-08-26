import SwiftUI

/// Sheet shown when a word is tapped after a reading: the verdict, what the
/// recognizer heard, and A/B audio — the user's slice vs a native reference.
struct WordDetailView: View {
    let word: PassageWord
    let result: WordResult
    let recordingURL: URL?

    @State private var coach = AudioCoach()
    @State private var phonemeScores: [PhonemeScorer.PhonemeScore]?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Text(word.display)
                    .font(.system(size: 40, weight: .regular, design: .serif))
                    .foregroundStyle(Theme.ink)
                verdictBadge
                Spacer()
            }

            if let ipa = Lexicon.ipa(for: word.norm) {
                Text("/ \(ipa) /")
                    .font(.system(size: 18, design: .serif))
                    .foregroundStyle(Theme.accent)
                    .accessibilityLabel("Expected pronunciation")
            }

            Text(verdictText)
                .font(.system(size: 15, weight: .regular, design: .serif))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            if let scores = phonemeScores {
                phonemeRow(scores)
            }

            Divider().overlay(Theme.line)

            HStack(spacing: 12) {
                audioButton("NATIVE", icon: "speaker.wave.2") {
                    coach.speakReference(word.display)
                }
                audioButton("SLOW", icon: "tortoise") {
                    coach.speakReference(word.display, slow: true)
                }
                if let url = recordingURL, let start = result.start, let duration = result.duration {
                    audioButton("YOUR TAKE", icon: "waveform") {
                        coach.playSlice(recording: url, start: start, duration: duration)
                    }
                }
            }
            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.paper)
        .onDisappear { coach.stopAll() }
        .task {
            // Tier-2 scores usually arrive with the take; fall back to
            // scoring this word's slice on demand.
            if let stored = result.phonemeScores {
                phonemeScores = stored
                return
            }
            guard let url = recordingURL,
                  let start = result.start, let duration = result.duration else { return }
            var loadedScorer = PhonemeScorer.ready
            if loadedScorer == nil { loadedScorer = await PhonemeScorer.loaded() }
            guard let scorer = loadedScorer else { return }
            let norm = word.norm
            phonemeScores = await Task.detached(priority: .userInitiated) {
                scorer.score(wordNorm: norm, recording: url, start: start, duration: duration)
            }.value
        }
    }

    /// One chip per expected phoneme, colored by its GOP verdict.
    private func phonemeRow(_ scores: [PhonemeScorer.PhonemeScore]) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(scores.enumerated()), id: \.offset) { _, score in
                let color: Color = switch PhonemeScorer.Verdict(gop: score.gop) {
                case .clean: Theme.ink
                case .accented: Theme.amber
                case .missed: Theme.accent
                }
                Text(score.ipa)
                    .font(.system(size: 18, weight: .medium, design: .serif))
                    .foregroundStyle(color)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(color.opacity(0.45), lineWidth: 1))
            }
            Spacer()
        }
        .accessibilityLabel("Phoneme scores")
    }

    private var verdictBadge: some View {
        Group {
            switch result.state {
            case .spoken:
                badge("CLEAN", color: Theme.muted)
            case .accented:
                badge("ACCENTED", color: Theme.amber)
            case .missed:
                badge("MISSED", color: Theme.accent)
            case .upcoming, .current:
                badge("NOT READ", color: Theme.upcoming)
            }
        }
    }

    private func badge(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .kerning(1.5)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .overlay(Capsule().stroke(color.opacity(0.5), lineWidth: 1))
    }

    private var verdictText: String {
        let confidenceNote = result.confidence.map { " (confidence \(Int($0 * 100))%)" } ?? ""
        switch result.state {
        case .spoken:
            return "Recognized cleanly\(confidenceNote)."
        case .accented:
            if let heard = result.heard {
                return "The recognizer got “\(heard)”, but only just\(confidenceNote). That hesitation usually means an accented vowel or consonant."
            }
            return "Recognized, but with low confidence\(confidenceNote)."
        case .missed:
            if let heard = result.heard {
                return "Heard “\(heard)” instead\(confidenceNote)."
            }
            return "Skipped — the recognizer never heard this word."
        case .upcoming, .current:
            return "This word wasn't read in the last take."
        }
    }

    private func audioButton(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                Text(label)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .kerning(1)
                    .fixedSize()
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .overlay(Capsule().stroke(Theme.line, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }
}
