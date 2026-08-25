import Foundation

/// How a passage word is rendered at a given moment of the reading.
enum WordState: Equatable {
    case upcoming   // not reached yet — faded
    case current    // being spoken now — amber wash
    case spoken     // matched cleanly — ink
    case missed     // mispronounced, substituted, or skipped — red underline
}

struct PassageWord: Identifiable {
    let id: Int
    let display: String   // as printed, with punctuation
    let norm: String      // normalized for matching
}

struct Passage {
    let words: [PassageWord]

    init(text: String) {
        words = text.split(separator: " ").enumerated().map { index, raw in
            PassageWord(id: index, display: String(raw), norm: Passage.normalize(String(raw)))
        }
    }

    static func normalize(_ word: String) -> String {
        word.lowercased()
            .filter { $0.isLetter || $0.isNumber || $0 == "'" }
            .replacingOccurrences(of: "'", with: "")
    }

    /// Align the recognizer's hypothesis tokens against the passage and produce
    /// a display state per word. Classic edit-distance alignment (match /
    /// substitution / omission / insertion) — small passages, so O(n·m) is free.
    ///
    /// `inProgress` marks the read as still live: trailing unread words stay
    /// `upcoming` and the first pending word becomes `current`. The last
    /// hypothesis token of a volatile result is often a half-recognized word,
    /// so if it is a strict prefix of the word it aligned to, that word is
    /// treated as in-progress rather than missed.
    func align(hypothesis: [String], inProgress: Bool) -> [WordState] {
        var states = [WordState](repeating: .upcoming, count: words.count)
        guard !hypothesis.isEmpty else {
            if inProgress, !words.isEmpty { states[0] = .current }
            return states
        }

        let n = words.count
        let m = hypothesis.count
        // dp[i][j] = cost of aligning first i passage words with first j tokens
        var dp = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        for i in 0...n { dp[i][0] = i }
        for j in 0...m { dp[0][j] = j }
        for i in 1...n {
            for j in 1...m {
                let subCost = words[i - 1].norm == hypothesis[j - 1] ? 0 : 1
                dp[i][j] = min(
                    dp[i - 1][j - 1] + subCost,  // match / substitution
                    dp[i - 1][j] + 1,            // passage word omitted
                    dp[i][j - 1] + 1)            // spurious token inserted
            }
        }

        // Backtrace, preferring matches, and record what happened to each passage word.
        enum Op { case match(Int), sub(Int, Int), del(Int) }
        var ops: [Op] = []
        var i = n, j = m
        while i > 0 || j > 0 {
            if i > 0, j > 0, dp[i][j] == dp[i - 1][j - 1] + (words[i - 1].norm == hypothesis[j - 1] ? 0 : 1) {
                if words[i - 1].norm == hypothesis[j - 1] {
                    ops.append(.match(i - 1))
                } else {
                    ops.append(.sub(i - 1, j - 1))
                }
                i -= 1; j -= 1
            } else if i > 0, dp[i][j] == dp[i - 1][j] + 1 {
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
            case .match(let p), .sub(let p, _): lastConsumed = max(lastConsumed, p)
            case .del: break
            }
        }

        for op in ops {
            switch op {
            case .match(let p):
                states[p] = .spoken
            case .sub(let p, let h):
                let token = hypothesis[h]
                let isLiveTail = inProgress && h == m - 1 && p == lastConsumed
                if isLiveTail && words[p].norm.hasPrefix(token) {
                    states[p] = .current  // half-recognized word still being spoken
                } else {
                    states[p] = .missed
                }
            case .del(let p):
                if p < lastConsumed { states[p] = .missed }  // skipped over
            }
        }

        if inProgress, let next = states.firstIndex(of: .upcoming) {
            // Only promote the next unread word if nothing is already marked current.
            if !states.contains(.current) { states[next] = .current }
        }
        return states
    }
}
