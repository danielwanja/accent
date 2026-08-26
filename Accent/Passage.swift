import Foundation

/// How a passage word is rendered at a given moment of the reading.
enum WordState: Equatable {
    case upcoming   // not reached yet — faded
    case current    // being spoken now — amber wash
    case spoken     // matched cleanly — ink
    case accented   // matched, but low ASR confidence — amber underline
    case missed     // mispronounced, substituted, or skipped — red underline
}

/// What happened to one passage word during a reading — display state plus the
/// evidence behind it, which feeds the word detail card.
struct WordResult: Equatable {
    var state: WordState = .upcoming
    var heard: String? = nil            // recognized token this word aligned to
    var confidence: Double? = nil
    var start: TimeInterval? = nil      // position in the session recording
    var duration: TimeInterval? = nil
    /// Tier-2: per-phoneme GOP scores, filled in after the take ends.
    var phonemeScores: [PhonemeScorer.PhonemeScore]? = nil
}

struct PassageWord: Identifiable {
    let id: Int
    let display: String   // as printed, with punctuation
    let norm: String      // normalized for matching
}

struct Passage {
    let text: String
    let words: [PassageWord]

    init(text: String) {
        self.text = text
        words = text.split(whereSeparator: \.isWhitespace).enumerated().map { index, raw in
            PassageWord(id: index, display: String(raw), norm: Passage.normalize(String(raw)))
        }
    }

    static func normalize(_ word: String) -> String {
        let filtered = word.lowercased()
            .filter { $0.isLetter || $0.isNumber || $0 == "'" }
            .replacingOccurrences(of: "'", with: "")
        // ASR writes digits ("three" → "3"); spell them out so both sides of
        // the alignment agree.
        if !filtered.isEmpty, filtered.allSatisfy(\.isNumber), let value = Int(filtered) {
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: "en_US")
            formatter.numberStyle = .spellOut
            if let spelled = formatter.string(from: NSNumber(value: value)) {
                return spelled.lowercased().filter(\.isLetter)
            }
        }
        return filtered
    }

    /// Align the recognizer's hypothesis against the passage and produce a
    /// result per word. Classic edit-distance alignment (match / substitution /
    /// omission / insertion) — small passages, so O(n·m) is free.
    ///
    /// `inProgress` marks the read as still live: trailing unread words stay
    /// `upcoming` and the first pending word becomes `current`. The last
    /// hypothesis token of a volatile result is often a half-recognized word,
    /// so if it is a strict prefix of the word it aligned to, that word is
    /// treated as in-progress rather than missed.
    func align(hypothesis: [TimedWord], inProgress: Bool) -> [WordResult] {
        var results = [WordResult](repeating: WordResult(), count: words.count)
        guard !hypothesis.isEmpty else {
            if inProgress, !words.isEmpty { results[0].state = .current }
            return results
        }

        let n = words.count
        let m = hypothesis.count
        // dp[i][j] = cost of aligning first i passage words with first j tokens
        var dp = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        for i in 0...n { dp[i][0] = i }
        for j in 0...m { dp[0][j] = j }
        for i in 1...n {
            for j in 1...m {
                let subCost = words[i - 1].norm == hypothesis[j - 1].norm ? 0 : 1
                dp[i][j] = min(
                    dp[i - 1][j - 1] + subCost,  // match / substitution
                    dp[i - 1][j] + 1,            // passage word omitted
                    dp[i][j - 1] + 1)            // spurious token inserted
            }
        }

        // Backtrace, preferring matches, and record what happened to each passage word.
        enum Op { case match(Int, Int), sub(Int, Int), del(Int) }
        var ops: [Op] = []
        var i = n, j = m
        while i > 0 || j > 0 {
            if i > 0, j > 0 {
                let isMatch = words[i - 1].norm == hypothesis[j - 1].norm
                let diagonal = dp[i - 1][j - 1] + (isMatch ? 0 : 1)
                if dp[i][j] == diagonal {
                    ops.append(isMatch ? .match(i - 1, j - 1) : .sub(i - 1, j - 1))
                    i -= 1; j -= 1
                    continue
                }
            }
            if i > 0, dp[i][j] == dp[i - 1][j] + 1 {
                ops.append(.del(i - 1))
                i -= 1
            } else {
                j -= 1  // insertion: extra spoken token, no passage word affected
            }
        }
        ops.reverse()

        // The furthest passage word that consumed a hypothesis token: deletions
        // beyond it are "not read yet", not skips.
        var lastConsumed = -1
        for op in ops {
            switch op {
            case .match(let p, _), .sub(let p, _): lastConsumed = max(lastConsumed, p)
            case .del: break
            }
        }

        for op in ops {
            switch op {
            case .match(let p, let h):
                results[p] = WordResult(
                    state: .spoken,
                    heard: hypothesis[h].text,
                    confidence: hypothesis[h].confidence,
                    start: hypothesis[h].start,
                    duration: hypothesis[h].duration)
            case .sub(let p, let h):
                let token = hypothesis[h]
                let isLiveTail = inProgress && h == m - 1 && p == lastConsumed
                if isLiveTail && words[p].norm.hasPrefix(token.norm) {
                    results[p].state = .current  // half-recognized word still being spoken
                } else {
                    results[p] = WordResult(
                        state: .missed,
                        heard: token.text,
                        confidence: token.confidence,
                        start: token.start,
                        duration: token.duration)
                }
            case .del(let p):
                if p < lastConsumed { results[p].state = .missed }  // skipped over
            }
        }

        if inProgress, let next = results.firstIndex(where: { $0.state == .upcoming }) {
            // Only promote the next unread word if nothing is already marked current.
            if !results.contains(where: { $0.state == .current }) { results[next].state = .current }
        }
        return results
    }
}
