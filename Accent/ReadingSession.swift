import Foundation
import Observation

/// Drives one live reading of the M0 passage: starts/stops the speech engine,
/// folds transcript updates into word states via the aligner.
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

    // A th-heavy sentence — the classic French-speaker sounds, on purpose.
    let passage = Passage(text: "I think these three brothers live near the theater.")

    private(set) var states: [WordState]
    private(set) var status: Status = .idle
    var isRecording: Bool { status == .listening }

    private let engine = SpeechEngine()
    private var prepared = false
    private var finalizedText = ""
    private var volatileText = ""

    init() {
        states = [WordState](repeating: .upcoming, count: passage.words.count)
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
            if !states.isEmpty { states[0] = .current }
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
        finalizedText = ""
        volatileText = ""
        states = [WordState](repeating: .upcoming, count: passage.words.count)
        if !keepStatus { status = .idle }
    }

    private func apply(_ update: SpeechEngine.Update) {
        let text = update.text.trimmingCharacters(in: .whitespaces)
        if update.isFinal {
            // An empty final means the recognizer reset without committing —
            // promote the volatile hypothesis rather than losing it.
            finalizedText += " " + (text.isEmpty ? volatileText : text)
            volatileText = ""
        } else {
            volatileText = text
        }
        realign(inProgress: isRecording)
    }

    private func realign(inProgress: Bool) {
        let tokens = (finalizedText + " " + volatileText)
            .split(separator: " ")
            .map { Passage.normalize(String($0)) }
            .filter { !$0.isEmpty }
        states = passage.align(hypothesis: tokens, inProgress: inProgress)
    }
}
