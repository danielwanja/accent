import Foundation

/// One recognized word, normalized across speech backends.
struct TimedWord {
    let text: String
    let norm: String
    /// 0…1 word confidence. SFSpeechRecognizer reports it on final results;
    /// SpeechAnalyzer doesn't expose one, so it stays nil there.
    let confidence: Double?
    /// Seconds from the start of the session recording.
    let start: TimeInterval?
    let duration: TimeInterval?

    /// Expands one recognizer chunk into per-word TimedWords. Both backends
    /// can hand back chunks spanning several words (on-device SFSpeech
    /// segments, analyzer attribute runs); aligning needs single words, and
    /// A/B slicing needs a per-word time range — so the chunk's range is
    /// apportioned across its words by character count.
    static func expand(text: String, confidence: Double?, start: TimeInterval?, duration: TimeInterval?) -> [TimedWord] {
        let pairs = text.split(whereSeparator: \.isWhitespace)
            .map { (String($0), Passage.normalize(String($0))) }
            .filter { !$0.1.isEmpty }
        guard !pairs.isEmpty else { return [] }
        guard pairs.count > 1, let start, let duration, duration > 0 else {
            return pairs.map { TimedWord(text: $0.0, norm: $0.1, confidence: confidence, start: start, duration: duration) }
        }
        let totalChars = pairs.reduce(0) { $0 + $1.1.count }
        var cursor = start
        return pairs.map { token, norm in
            let share = duration * Double(norm.count) / Double(totalChars)
            defer { cursor += share }
            return TimedWord(text: token, norm: norm, confidence: confidence, start: cursor, duration: share)
        }
    }
}
