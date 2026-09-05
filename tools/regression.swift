import Foundation
import Speech
import CoreMedia

@main
struct Regression {
    static func main() throws {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            guard condition() else { fatalError("FAIL: \(message)") }
            count += 1
        }
        func tokens(_ text: String, start: Double? = nil, duration: Double? = nil) -> [TimedWord] {
            TimedWord.expand(text: text, confidence: nil, start: start, duration: duration)
        }
        // Every prefix must stop at the right word, even with repeated phrases.
        for text in [
            "the cat saw the cat near the cat",
            "This Thursday three brothers heard that the harbor hotel had a heated pool. Please sit in this seat and feel the deep heat. They walked, asked questions, and watched the ships arrive. Development of a rich vocabulary is necessary, whether you catch each chance or not.",
            "we read this and we read this and we read this"
        ] {
            let passage = Passage(text: text)
            for n in 0...passage.words.count {
                let hypothesis = tokens(passage.words.prefix(n).map(\.display).joined(separator: " "))
                let result = passage.align(hypothesis: hypothesis, inProgress: true)
                check(result.prefix(n).allSatisfy { $0.state == .spoken }, "spoken prefix \(n)")
                check(result.filter { $0.state == .current }.count == (n == passage.words.count ? 0 : 1), "single cursor \(n)")
                if n < passage.words.count { check(result[n].state == .current, "correct frontier \(n)") }
                check(result.dropFirst(n + 1).allSatisfy { $0.state == .upcoming }, "unread suffix \(n)")
            }
        }
        check(Passage(text: "").align(hypothesis: tokens("hello"), inProgress: true).isEmpty, "empty passage")
        let skipped = Passage(text: "one two three four five").align(hypothesis: tokens("one three four"), inProgress: false)
        check(skipped[1].state == .uncertain && skipped[3].state == .spoken && skipped[4].state == .upcoming, "skip doesn't score or advance suffix")
        let extra = Passage(text: "the cat is sleeping").align(hypothesis: tokens("the the cat is"), inProgress: true)
        check(extra[3].state == .current, "repeated spoken word is an insertion")
        let wrong = Passage(text: "the red cat sleeps").align(hypothesis: tokens("the blue cat"), inProgress: false)
        check(wrong[1].state == .uncertain, "ASR mismatch isn't a pronunciation error")
        let partial = Passage(text: "we gather there").align(hypothesis: tokens("we gath"), inProgress: true)
        check(partial[1].state == .current && partial[2].state == .upcoming, "partial word stays current")

        var buffer = TranscriptBuffer()
        buffer.apply(words: tokens("we read", start: 0, duration: 1), isFinal: false, range: 0..<1)
        buffer.apply(words: tokens("we read this", start: 0, duration: 1.5), isFinal: true, range: 0..<1.5)
        buffer.apply(words: tokens("we read this", start: 1.5, duration: 1.5), isFinal: false, range: 1.5..<3)
        buffer.apply(words: tokens("we read that", start: 1.5, duration: 1.5), isFinal: true, range: 1.5..<3)
        check(buffer.words.map(\.norm) == ["we", "read", "this", "we", "read", "that"], "revisions replace; repeated new audio survives")
        buffer.apply(words: tokens("we read that", start: 1.5, duration: 1.5), isFinal: true, range: 1.5..<3)
        check(buffer.words.count == 6, "duplicate finals aren't appended")
        buffer.apply(words: [], isFinal: true, range: 1.5..<3)
        check(buffer.words.count == 3, "empty ranged correction removes volatile words")
        var partialFinal = TranscriptBuffer()
        partialFinal.apply(words: tokens("one two three four", start: 0, duration: 4), isFinal: false, range: 0..<4)
        partialFinal.apply(words: tokens("one two", start: 0, duration: 2), isFinal: true, range: 0..<2)
        check(partialFinal.words.map(\.norm) == ["one", "two", "three", "four"], "partial final preserves later volatile audio")
        partialFinal.apply(words: tokens("three five", start: 2, duration: 2), isFinal: true, range: 2..<4)
        check(partialFinal.words.map(\.norm) == ["one", "two", "three", "five"], "later partial revision replaces only its range")
        let existing = tokens("a", start: 0, duration: 0.08)
        check(TimedWord.dedup(existing: existing, incoming: existing + tokens("cat", start: 0.08, duration: 0.4)).map(\.norm) == ["cat"], "short words not duplicated at frontier")
        var legacy = TranscriptBuffer()
        legacy.apply(words: tokens("one two"), isFinal: false)
        legacy.apply(words: [], isFinal: true)
        legacy.apply(words: tokens("one two three"), isFinal: false)
        check(legacy.words.map(\.norm) == ["one", "two", "three"], "legacy reset and cumulative partial")

        var fragmented = AttributedString("ga")
        fragmented.audioTimeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: 0.1, preferredTimescale: 100))
        var tail = AttributedString("ther there")
        tail.audioTimeRange = CMTimeRange(start: CMTime(seconds: 0.1, preferredTimescale: 100), duration: CMTime(seconds: 0.9, preferredTimescale: 100))
        fragmented += tail
        check(TimedWord.from(transcript: fragmented).map(\.norm) == ["gather", "there"], "attribute fragments remain one word")
        let fragmentTiming = TimedWord.from(transcript: fragmented)
        check(fragmentTiming.allSatisfy(\.estimated) && fragmentTiming[1].start! >= fragmentTiming[0].start! + fragmentTiming[0].duration!, "overlapping fragment timings are apportioned")
        var shared = AttributedString("one two three")
        shared.audioTimeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: 1, preferredTimescale: 100))
        let expanded = TimedWord.from(transcript: shared)
        check(expanded.allSatisfy(\.estimated) && expanded[2].start! > expanded[1].start!, "shared word timestamps stay estimated")

        check(PhonemeScorer.align(logProbs: [], candidates: [[0]], blankID: 1) == nil, "empty CTC input")
        check(PhonemeScorer.align(logProbs: [[-1, -2]], candidates: [[3]], blankID: 1) == nil, "invalid CTC labels")
        let repeated = PhonemeScorer.align(logProbs: [[0, -10], [-10, 0], [0, -10]], candidates: [[0], [0]], blankID: 1)
        check(repeated == [[0], [2]], "repeated phones require separating blank")
        check(!PhonemeScorer.PhonemeScore(arpa: "TH", ipa: "θ", gop: -9, evidenceFrames: 0, competingIPA: "s").needsPractice, "no acoustic evidence cannot flag")
        check(!PhonemeScorer.PhonemeScore(arpa: "HH", ipa: "h", gop: -9, evidenceFrames: 4, competingIPA: "a").needsPractice, "unreliable h cannot flag")
        check(!PhonemeScorer.PhonemeScore(arpa: "TH", ipa: "θ", gop: -2, evidenceFrames: 4, competingIPA: "s").needsPractice, "mild difference is neutral")
        check(PhonemeScorer.PhonemeScore(arpa: "TH", ipa: "θ", gop: -7, evidenceFrames: 4, competingIPA: "s").needsPractice, "supported substitution gets practice cue")
        check(!PhonemeScorer.PhonemeScore(arpa: "IY", ipa: "i", gop: -7, evidenceFrames: 1, competingIPA: "l").needsPractice, "neighboring consonant isn't a vowel correction")
        check(!Phonics.practiceCue(forPhone: "TH").isEmpty, "articulation cue exists")
        let lowConfidence = Passage(text: "think").align(hypothesis: [TimedWord(text: "think", norm: "think", confidence: 0.01, start: 0, duration: 0.4)], inProgress: false)
        check(lowConfidence[0].state == .spoken, "recognizer confidence doesn't judge accent")
        let take = TakeRecord(date: Date(), passageTitle: "test", passageText: "think", words: [
            StoredWord(display: "think", norm: "think", state: "accented", heard: "think", confidence: nil,
                       phonemes: [StoredPhoneme(arpa: "TH", gop: -5, needsPractice: true, assessed: true)]),
            StoredWord(display: "think", norm: "think", state: "uncertain", heard: "sink", confidence: nil),
            StoredWord(display: "think", norm: "think", state: "spoken", heard: "think", confidence: nil,
                       phonemes: [StoredPhoneme(arpa: "TH", gop: 0, needsPractice: false, assessed: false)])
        ], recordingFile: nil)
        let th = IssueProfile.stats(from: [take]).first { $0.id == "th" }
        check(th?.attempts == 1 && th?.misses == 1, "uncertain and unassessed sounds excluded from progress")
        check(take.understoodCount == 2, "recognition count is separate from sound practice")
        let legacyWord = try JSONDecoder().decode(StoredWord.self, from: Data(#"{"display":"think","norm":"think","state":"accented","heard":"think","confidence":0.2,"phonemes":[{"arpa":"TH","gop":-5}]}"#.utf8))
        check(legacyWord.phonemes?.first?.assessed == nil, "old saved takes still decode")
        let oldTake = TakeRecord(date: Date(), passageTitle: "old", passageText: "think", words: [legacyWord], recordingFile: nil)
        check(IssueProfile.stats(from: [oldTake]).isEmpty, "old uncalibrated evidence doesn't contaminate new sound progress")
        print("PASS: \(count) regression checks")
    }
}
