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

    /// Drops the longest prefix of `incoming` that repeats the tail of
    /// `existing` (matched on normalized text). The analyzer's volatile —
    /// and sometimes final — hypotheses are cumulative from session start,
    /// so without this the aligner briefly sees the whole text twice and
    /// marks everything as missed. SFSpeech chunks don't overlap, so this
    /// is a no-op there.
    static func trimOverlap(existing: [TimedWord], incoming: [TimedWord]) -> [TimedWord] {
        var k = min(existing.count, incoming.count)
        while k > 0 {
            var matches = true
            for i in 0..<k where existing[existing.count - k + i].norm != incoming[i].norm {
                matches = false
                break
            }
            if matches { break }
            k -= 1
        }
        return Array(incoming.dropFirst(k))
    }

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
