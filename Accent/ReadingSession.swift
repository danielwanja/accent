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
        status = .finished
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
            finalizedWords += update.words.isEmpty ? volatileWords : update.words
            volatileWords = []
        } else {
            volatileWords = update.words
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
