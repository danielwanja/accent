import Foundation
import Observation

/// Drives one live reading of a passage: starts/stops the speech engine and
/// folds transcript updates into per-word results via the aligner.
@MainActor
@Observable
final class ReadingSession {
    enum Status: Equatable {
        case idle
        case preparing
        case listening
        case scoring    // take ended, phoneme scoring in flight
        case finished
        case failed(String)
    }

    private(set) var passage: Passage
    private(set) var passageTitle: String
    private(set) var results: [WordResult]
    private(set) var status: Status = .idle
    var isRecording: Bool { status == .listening }
    var recordingURL: URL? { engine.recordingURL }

    // Tier-1 scoring: a matched word whose ASR confidence falls below this is
    // marked "accented" — right word, but the recognizer had to squint.
    private let accentedThreshold = 0.45

    private let engine = SpeechEngine()
    private var prepared = false
    private var finalizedWords: [TimedWord] = []
    private var volatileWords: [TimedWord] = []

    init() {
        let first = PassageLibrary.curated[0]
        let passage = Passage(text: first.text)
        self.passage = passage
        passageTitle = first.title
        results = [WordResult](repeating: WordResult(), count: passage.words.count)
    }

    func load(title: String, text: String) {
        guard !isRecording else { return }
        passage = Passage(text: text)
        passageTitle = title
        reset()
    }

    func toggle() {
        if isRecording {
            Task { await stop() }
        } else {
            Task { await start() }
        }
    }

    func start() async {
        guard status != .preparing else { return }
        status = .preparing
        reset(keepStatus: true)
        do {
            if !prepared {
                try await engine.prepare()
                prepared = true
            }
            try await engine.start { [weak self] update in
                self?.apply(update)
            }
            if !results.isEmpty { results[0].state = .current }
            status = .listening
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func stop() async {
        await engine.stop()
        // Final pass: no in-progress word, trailing words stay upcoming.
        realign(inProgress: false)
        await scorePhonemes()
        status = .finished
    }

    /// Tier-2 pass: GOP-score each read word's audio slice and let strong
    /// phoneme evidence upgrade the word verdict — this is what catches the
    /// substitutions ASR normalizes away ("zis" transcribed as "this").
    private func scorePhonemes() async {
        // Never wait for the model: if the background load hasn't finished
        // (first device launch), this take stays tier-1 and the next one
        // gets phoneme scoring.
        guard let scorer = PhonemeScorer.ready else {
            print("ACCENT tier-2 skipped: scorer not ready yet")
            return
        }
        guard let url = engine.recordingURL else { return }
        let jobs: [(Int, String, TimeInterval, TimeInterval, Bool)] = results.indices.compactMap { index in
            let r = results[index]
            guard r.state == .spoken || r.state == .accented || r.state == .missed,
                  let start = r.start, let duration = r.duration else { return nil }
            return (index, passage.words[index].norm, start, duration, r.timingEstimated)
        }
        guard !jobs.isEmpty else { return }
        status = .scoring
        let scored = await Task.detached(priority: .userInitiated) {
            // Budget the pass: on a slow compute path, partial tier-2 beats a
            // frozen-looking screen.
            let deadline = Date().addingTimeInterval(12)
            var out: [(Int, [PhonemeScorer.PhonemeScore])] = []
            for (index, norm, start, duration, estimated) in jobs {
                if Date() > deadline {
                    print("ACCENT tier-2 budget hit after \(out.count)/\(jobs.count) words")
                    break
                }
                if let scores = scorer.score(
                    wordNorm: norm, recording: url, start: start,
                    duration: duration, estimatedTiming: estimated) {
                    out.append((index, scores))
                }
            }
            return out
        }.value
        for (index, scores) in scored {
            results[index].phonemeScores = scores
            // Upgrade only — tier 2 can worsen a verdict, never absolve one.
            // Word-level thresholds sit looser than the per-phoneme chips:
            // slice boundaries are estimates, and edge-clipped phones score
            // worse than they were spoken (coach, not judge).
            if results[index].state == .spoken, let worst = scores.map(\.gop).min() {
                if worst < -6 { results[index].state = .missed }
                else if worst < -2 { results[index].state = .accented }
            }
        }
    }

    func reset(keepStatus: Bool = false) {
        finalizedWords = []
        volatileWords = []
        results = [WordResult](repeating: WordResult(), count: passage.words.count)
        if !keepStatus { status = .idle }
    }

    private func apply(_ update: SpeechEngine.Update) {
        if update.isFinal {
            // An empty final means the recognizer reset without committing —
            // promote the volatile hypothesis rather than losing it.
            finalizedWords += update.words.isEmpty
                ? volatileWords
                : TimedWord.dedup(existing: finalizedWords, incoming: update.words)
            volatileWords = []
        } else {
            // Analyzer volatiles restate (and revise) already-finalized audio.
            volatileWords = TimedWord.dedup(existing: finalizedWords, incoming: update.words)
        }
        realign(inProgress: isRecording)
    }

    private func realign(inProgress: Bool) {
        results = passage.align(hypothesis: finalizedWords + volatileWords, inProgress: inProgress)
        if !inProgress {
            for index in results.indices where results[index].state == .spoken {
                if let confidence = results[index].confidence, confidence < accentedThreshold {
                    results[index].state = .accented
                }
            }
        }
    }
}
