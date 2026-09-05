import Foundation

/// Analyzer revisions replace audio ranges; they are not new spoken words.
/// Keep phrase ranges even when individual word timestamps are estimates.
struct TranscriptBuffer {
    struct Segment {
        let range: Range<TimeInterval>
        let words: [TimedWord]
    }
    private var segments: [Segment] = []
    private var committed: [TimedWord] = []
    private var pending: [TimedWord] = []

    var words: [TimedWord] {
        segments.isEmpty ? committed + pending : segments.flatMap(\.words)
    }

    mutating func apply(words: [TimedWord], isFinal: Bool, range: Range<TimeInterval>? = nil) {
        if let range, range.lowerBound.isFinite, range.upperBound.isFinite, !range.isEmpty {
            // Keep only audio outside the revised phrase. This also handles a
            // final result covering only part of an earlier volatile result.
            segments = segments.flatMap { segment -> [Segment] in
                guard segment.range.overlaps(range) else { return [segment] }
                var retained: [Segment] = []
                func keep(_ remainder: Range<TimeInterval>) {
                    let kept = segment.words.filter { word in
                        guard let start = word.start else { return false }
                        return remainder.contains(start + (word.duration ?? 0) / 2)
                    }
                    if !kept.isEmpty { retained.append(Segment(range: remainder, words: kept)) }
                }
                if segment.range.lowerBound < range.lowerBound {
                    keep(segment.range.lowerBound..<range.lowerBound)
                }
                if segment.range.upperBound > range.upperBound {
                    keep(range.upperBound..<segment.range.upperBound)
                }
                return retained
            }
            segments.append(Segment(range: range, words: words))
            segments.sort { $0.range.lowerBound < $1.range.lowerBound }
        } else if isFinal {
            committed += words.isEmpty ? pending : TimedWord.dedup(existing: committed, incoming: words)
            pending = []
        } else {
            pending = TimedWord.dedup(existing: committed, incoming: words)
        }
    }
}
