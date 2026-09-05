import Foundation
import Speech

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
    /// True when start/duration were apportioned from a chunk spanning
    /// several words — boundaries are then estimates, not measurements.
    var estimated: Bool = false

    /// Removes from `incoming` whatever restates audio that `existing`
    /// already covers. The analyzer's hypotheses are cumulative from session
    /// start AND it revises words when restating them, so text matching alone
    /// is brittle — prefer the audio timeline: drop words starting before the
    /// finalized frontier. Falls back to exact text-overlap trimming when
    /// timestamps are absent (SFSpeech partials).
    static func dedup(existing: [TimedWord], incoming: [TimedWord]) -> [TimedWord] {
        let frontier = existing.compactMap { word in word.start.map { $0 + (word.duration ?? 0) } }.max()
        if let frontier, incoming.contains(where: { $0.start != nil }) {
            return incoming.filter { word in
                guard let start = word.start else { return true }
                // Midpoints prevent short finalized words from being appended twice.
                return start + (word.duration ?? 0) / 2 >= frontier - 0.015
            }
        }
        return trimOverlap(existing: existing, incoming: incoming)
    }

    /// Drops the longest prefix of `incoming` that exactly repeats the tail
    /// of `existing` (matched on normalized text). SFSpeech chunks don't
    /// overlap, so this is a no-op there.
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
            return TimedWord(text: token, norm: norm, confidence: confidence,
                             start: cursor, duration: share, estimated: true)
        }
    }
}

extension TimedWord {
    /// Flattens an analyzer transcript into words. Each attributed run carries
    /// an `audioTimeRange`; a run spanning several words gets its range
    /// apportioned across them by expand().
    static func from(transcript: AttributedString) -> [TimedWord] {
        // Split the complete text first. Attribute runs can split a word
        // into graphemes, which must never become separate recognized words.
        var words: [TimedWord] = []
        for token in transcript.characters.split(whereSeparator: \.isWhitespace) {
            let text = String(token)
            let norm = Passage.normalize(text)
            guard !norm.isEmpty else { continue }
            let ranges = transcript[token.startIndex..<token.endIndex].runs.compactMap { $0.audioTimeRange }
            let start = ranges.map { $0.start.seconds }.min()
            let end = ranges.map { $0.end.seconds }.max()
            words.append(TimedWord(text: text, norm: norm, confidence: nil,
                                   start: start, duration: start.flatMap { lo in end.map { $0 - lo } }))
        }
        // Shared phrase timestamps are estimates; apportion them only after
        // recovering whole words, keeping that uncertainty for playback/scoring.
        var cursor = 0
        while cursor < words.count {
            guard let groupStart = words[cursor].start, let firstDuration = words[cursor].duration else {
                cursor += 1
                continue
            }
            var groupEnd = groupStart + firstDuration
            var end = cursor + 1
            while end < words.count, let nextStart = words[end].start, let nextDuration = words[end].duration,
                  nextStart < groupEnd - 0.001 {
                groupEnd = max(groupEnd, nextStart + nextDuration)
                end += 1
            }
            if end - cursor > 1 {
                let expanded = TimedWord.expand(text: words[cursor..<end].map(\.text).joined(separator: " "),
                                               confidence: nil, start: groupStart,
                                               duration: groupEnd - groupStart)
                words.replaceSubrange(cursor..<end, with: expanded)
            }
            cursor = end
        }
        return words
    }

}
