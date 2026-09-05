import Foundation
import SwiftData

/// One phoneme's tier-2 outcome inside a saved word.
struct StoredPhoneme: Codable {
    let arpa: String           // stress-stripped ARPAbet ("TH")
    let gop: Double
    var needsPractice: Bool? = nil
    var assessed: Bool? = nil
}

/// One word's outcome inside a saved take.
struct StoredWord: Codable {
    let display: String
    let norm: String
    let state: String          // "spoken" | "accented" | "missed"
    let heard: String?
    let confidence: Double?
    var phonemes: [StoredPhoneme]? = nil   // optional: absent on pre-tier-2 takes
    var stressOK: Bool? = nil              // tier-3 lexical stress verdict
}

/// One completed reading, persisted.
@Model
final class TakeRecord {
    var date: Date
    var passageTitle: String
    var passageText: String
    var wordsData: Data        // [StoredWord]
    var recordingFile: String? // filename under Documents/Recordings

    init(date: Date, passageTitle: String, passageText: String, words: [StoredWord], recordingFile: String?) {
        self.date = date
        self.passageTitle = passageTitle
        self.passageText = passageText
        self.wordsData = (try? JSONEncoder().encode(words)) ?? Data()
        self.recordingFile = recordingFile
    }

    var words: [StoredWord] {
        (try? JSONDecoder().decode([StoredWord].self, from: wordsData)) ?? []
    }

    var readCount: Int { words.count }
    var understoodCount: Int {
        words.filter { word in
            word.heard.map { Passage.normalize($0) == word.norm } ?? (word.state == "spoken")
        }.count
    }
}

/// Aggregated per-issue mastery, computed from take history.
struct IssueStat: Identifiable {
    let issue: Issue
    let attempts: Int          // words read that exercise this issue
    let misses: Int            // of those, flagged accented or missed
    var id: String { issue.id }
    var mastery: Double { attempts == 0 ? 0 : 1 - Double(misses) / Double(attempts) }
}

enum IssueProfile {
    /// Per-issue stats over the given takes, most-practiced issues included even
    /// when clean. Only words that were actually read count as attempts.
    static func stats(from takes: [TakeRecord]) -> [IssueStat] {
        var attempts: [String: Int] = [:]
        var misses: [String: Int] = [:]
        for take in takes {
            for word in take.words {
                guard word.state != "uncertain",
                      word.phonemes?.contains(where: { $0.assessed != nil }) == true else { continue }
                // Count only assessed sounds from the current evidence policy.
                // Keep earlier takes in history without reusing their uncalibrated
                // scores or ASR uncertainty as sound mastery measurements.
                var phonemeMissed: Set<String> = []
                var phonemeJudged: Set<String> = []
                for phoneme in word.phonemes ?? [] {
                    // Unreliable or unassessed sounds do not affect mastery.
                    guard !PhonemeScorer.lowConfidencePhones.contains(phoneme.arpa),
                          phoneme.assessed == true else { continue }
                    for id in Phonics.issueIDs(forPhone: phoneme.arpa) {
                        phonemeJudged.insert(id)
                        if phoneme.needsPractice == true { phonemeMissed.insert(id) }
                    }
                }
                for id in Phonics.issueIDs(for: word.norm) {
                    let missed: Bool
                    if id == "stress", let stressOK = word.stressOK {
                        missed = !stressOK      // tier-3 measured it directly
                    } else if phonemeJudged.contains(id) {
                        missed = phonemeMissed.contains(id)
                    } else {
                        continue // Recognition uncertainty cannot measure sound mastery.
                    }
                    attempts[id, default: 0] += 1
                    if missed { misses[id, default: 0] += 1 }
                }
            }
        }
        return Phonics.issues.compactMap { issue in
            guard let count = attempts[issue.id], count > 0 else { return nil }
            return IssueStat(issue: issue, attempts: count, misses: misses[issue.id] ?? 0)
        }
        .sorted { $0.mastery < $1.mastery }
    }

    /// The issue most worth practicing: lowest mastery among issues with enough
    /// evidence, preferring ones that actually missed.
    static func focus(from takes: [TakeRecord]) -> IssueStat? {
        let all = stats(from: takes)
        return all.first { $0.attempts >= 3 && $0.misses > 0 } ?? all.first { $0.misses > 0 }
    }
}
