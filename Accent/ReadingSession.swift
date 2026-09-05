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

    private let engine = SpeechEngine()
    private var prepared = false
    private var transcript = TranscriptBuffer()
    private var takeID = UUID()
    private var acceptingUpdates = false
    var isBusy: Bool { status == .preparing || status == .listening || status == .scoring }
    private(set) var scoringAvailable = false

    init() {
        let first = PassageLibrary.curated[0]
        let passage = Passage(text: first.text)
        self.passage = passage
        passageTitle = first.title
        results = [WordResult](repeating: WordResult(), count: passage.words.count)
    }

    func load(title: String, text: String) {
        guard !isBusy else { return }
        passage = Passage(text: text)
        passageTitle = title
        reset()
    }

    #if DEBUG
    /// Illustrative fixture for documentation screenshots, never a scored recording.
    /// AccentApp uses an in-memory store and skips model/microphone work in this mode.
    func loadScreenshotDemo() {
        let sample = PassageLibrary.curated[0]
        load(title: sample.title, text: sample.text)
        results = passage.words.map { word in
            if word.norm == "think" {
                return WordResult(state: .accented, phonemeScores: [
                    .init(arpa: "TH", ipa: "θ", gop: -4, evidenceFrames: 2, competingIPA: "s"),
                    .init(arpa: "IH", ipa: "ɪ", gop: 0, evidenceFrames: 2, stressed: true),
                    .init(arpa: "NG", ipa: "ŋ", gop: 0, evidenceFrames: 2),
                    .init(arpa: "K", ipa: "k", gop: 0, evidenceFrames: 2)
                ])
            }
            return WordResult(state: .spoken)
        }
        scoringAvailable = true
        status = .finished
    }
    #endif

    func toggle() {
        if isRecording {
            Task { await stop() }
        } else {
            Task { await start() }
        }
    }

    func start() async {
        guard !isBusy else { return }
        status = .preparing
        reset(keepStatus: true)
        let id = takeID
        acceptingUpdates = true
        do {
            if !prepared {
                try await engine.prepare()
                prepared = true
            }
            try await engine.start { [weak self] update in
                guard self?.takeID == id else { return }
                self?.apply(update)
            }
            status = .listening
            realign(inProgress: true)
        } catch {
            await engine.stop()
            acceptingUpdates = false
            status = .failed(error.localizedDescription)
        }
    }

    func stop() async {
        guard isRecording else { return }
        status = .scoring
        await engine.stop()
        acceptingUpdates = false
        // Final pass: no in-progress word, trailing words stay upcoming.
        realign(inProgress: false)
        await scorePhonemes()
        status = .finished
    }

    /// Score bounded chunks of the actual transcript, including repetitions
    /// and inserted words. Never force omitted passage words into the audio.
    private func scorePhonemes() async {
        guard let scorer = PhonemeScorer.ready, let url = engine.recordingURL else { return }
        let spoken = transcript.words
        let snapshot = results
        let passageWords = passage.words
        let id = takeID
        let scored = await Task.detached(priority: .userInitiated) {
            var output: [Int: PhonemeScorer.WordAlignment] = [:]
            var cursor = 0
            while cursor < spoken.count {
                let first = cursor
                guard let start = spoken[first].start else { cursor += 1; continue }
                var end = start
                while cursor < spoken.count,
                      let wordStart = spoken[cursor].start,
                      let duration = spoken[cursor].duration, duration > 0,
                      wordStart + duration - start <= 12 {
                    end = wordStart + duration
                    cursor += 1
                }
                guard cursor > first else { cursor += 1; continue }
                let chunk = Array(spoken[first..<cursor])
                let phones = chunk.map { Lexicon.phones(for: $0.norm) ?? [] }
                // Unknown words cannot be silently removed from a forced path.
                guard phones.allSatisfy({ !$0.isEmpty }) else { continue }
                let windowStart = max(0, start - 0.12)
                guard let aligned = scorer.scoreUtterance(recording: url, wordPhones: phones,
                                                          start: windowStart, duration: end - windowStart + 0.12) else { continue }
                for index in snapshot.indices {
                    guard let h = snapshot[index].hypothesisIndex, (first..<cursor).contains(h),
                          spoken[h].norm == passageWords[index].norm,
                          let alignment = aligned[h - first],
                          let asrStart = spoken[h].start, let asrDuration = spoken[h].duration else { continue }
                    let tolerance = spoken[h].estimated ? 0.6 : 0.3
                    // Keep suspect boundaries out of both scoring and word playback.
                    guard alignment.duration >= 0.06,
                          alignment.start >= asrStart - tolerance,
                          alignment.start + alignment.duration <= asrStart + asrDuration + tolerance else { continue }
                    output[index] = alignment
                }
            }
            return output
        }.value
        guard id == takeID else { return }
        for (index, alignment) in scored {
            results[index].start = alignment.start
            results[index].duration = alignment.duration
            results[index].timingEstimated = false
            // Reduced function words and ambiguous dictionary entries need
            // context-sensitive pronunciation variants before judging them.
            guard !Lexicon.requiresContext.contains(passage.words[index].norm) else { continue }
            results[index].phonemeScores = alignment.scores
            scoringAvailable = scoringAvailable || alignment.scores.contains { $0.isAssessed }
            // Energy × duration alone isn't reliable evidence of lexical stress.
            // Keep expected stress in the phone display, without penalizing it.
            results[index].state = alignment.scores.contains(where: \.needsPractice) ? .accented : .spoken
        }
    }

    func reset(keepStatus: Bool = false) {
        guard keepStatus || !isBusy else { return }
        takeID = UUID()
        acceptingUpdates = false
        transcript = TranscriptBuffer()
        scoringAvailable = false
        results = [WordResult](repeating: WordResult(), count: passage.words.count)
        if !keepStatus { status = .idle }
    }

    private func apply(_ update: SpeechEngine.Update) {
        guard acceptingUpdates else { return }
        transcript.apply(words: update.words, isFinal: update.isFinal, range: update.range)
        realign(inProgress: isRecording)
    }

    private func realign(inProgress: Bool) {
        results = passage.align(hypothesis: transcript.words, inProgress: inProgress)
    }
}
