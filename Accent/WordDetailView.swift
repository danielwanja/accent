import SwiftUI

/// A word's recognition evidence, an actionable sound cue, and A/B playback.
struct WordDetailView: View {
    let word: PassageWord
    let result: WordResult
    let recordingURL: URL?
    @State private var coach = AudioCoach()

    private var focus: PhonemeScorer.PhonemeScore? {
        result.phonemeScores?.filter(\.needsPractice).min { $0.gop < $1.gop }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Text(word.display)
                        .font(.system(size: 34, weight: .regular, design: .serif))
                        .foregroundStyle(Theme.ink)
                    Text(badge)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(focus == nil ? Theme.muted : Theme.amber)
                    Spacer()
                }

                if let ipa = Lexicon.ipa(for: word.norm) {
                    Text("/ \(ipa) /")
                        .font(.system(size: 18, design: .serif))
                        .foregroundStyle(Theme.ink)
                        .accessibilityLabel("Reference pronunciation")
                }

                Text(verdictText)
                    .font(.system(size: 15, design: .serif))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                if let scores = result.phonemeScores {
                    ScrollView(.horizontal) {
                        HStack(spacing: 6) {
                            ForEach(Array(scores.enumerated()), id: \.offset) { _, score in
                                Text((score.stressed ? "ˈ" : "") + score.ipa)
                                    .font(.system(size: 18, design: .serif))
                                    .foregroundStyle(score.needsPractice ? Theme.amber : Theme.muted)
                                    .padding(7)
                                    .overlay(RoundedRectangle(cornerRadius: 7)
                                        .stroke(score.needsPractice ? Theme.amber : Theme.line))
                                    .accessibilityLabel("\(score.ipa): \(score.needsPractice ? "try practicing" : "no correction suggested")")
                            }
                        }
                    }
                }

                if let focus {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TRY /\(focus.ipa)/")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.amber)
                        Text(Phonics.practiceCue(forPhone: focus.arpa))
                            .font(.system(size: 16, design: .serif))
                            .foregroundStyle(Theme.ink)
                        Text("Listen slowly, say “\(word.display)” three times with this mouth position, then read it in the sentence at your normal pace.")
                            .font(.system(size: 14, design: .serif))
                            .foregroundStyle(Theme.muted)
                    }
                } else {
                    Text("Listen to the reference, repeat the word, then put it back in the sentence. You do not need to match the reference voice or speed.")
                        .font(.system(size: 14, design: .serif))
                        .foregroundStyle(Theme.muted)
                }

                Divider().overlay(Theme.line)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { audioControls }
                    VStack(alignment: .leading, spacing: 10) { audioControls }
                }
                if result.timingEstimated, result.start != nil {
                    Text("Your clip includes nearby sounds because the word timing is approximate.")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
            }
            .padding(24)
        }
        .accessibilityIdentifier("wordDetailsContent")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paper)
        .onDisappear { coach.stopAll() }
    }

    private var badge: String {
        switch result.state {
        case .spoken: return "UNDERSTOOD"
        case .accented, .missed: return "PRACTICE"
        case .uncertain: return "CHECK AUDIO"
        case .upcoming, .current: return "NOT REACHED"
        }
    }

    private var verdictText: String {
        if let focus {
            return "The word was understood. The sound check suggests reviewing /\(focus.ipa)/. Listen to both clips first; this is a practice suggestion, not a definite error."
        }
        switch result.state {
        case .spoken:
            if result.phonemeScores?.contains(where: { $0.isAssessed }) == true {
                return "The word was understood, with no strong sound difference detected."
            }
            return "The word was understood. There isn't enough reliable sound evidence to assess its pronunciation in this take."
        case .uncertain, .missed, .accented:
            if let heard = result.heard {
                return "The recognizer wrote “\(heard)”. This can happen with natural pronunciation too. Replay your clip before deciding whether to practice."
            }
            return "This word wasn't matched in the transcript. It may have been skipped or missed by recognition; that does not establish a pronunciation error."
        case .upcoming, .current:
            return "This word wasn't reached in the last take. You can still listen and practice it."
        }
    }

    @ViewBuilder private var audioControls: some View {
        audioButton("REFERENCE", icon: "speaker.wave.2") { coach.speakReference(word.display) }
        audioButton("SLOW", icon: "tortoise") { coach.speakReference(word.display, slow: true) }
        if let url = recordingURL, let start = result.start, let duration = result.duration {
            audioButton("YOUR TAKE", icon: "waveform") {
                coach.playSlice(recording: url, start: start, duration: duration,
                                pad: result.timingEstimated ? 0.25 : 0.12)
            }
        }
    }

    private func audioButton(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .fixedSize()
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .overlay(Capsule().stroke(Theme.line, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("audio-\(label)")
    }
}
