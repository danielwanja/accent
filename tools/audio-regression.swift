import Foundation

@main
struct AudioRegression {
    static func main() throws {
        setbuf(stdout, nil)
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let tmp = URL(fileURLWithPath: CommandLine.arguments[1])
        let scorer = try PhonemeScorer(modelURL: root.appendingPathComponent("tools/models/PhonemeRecognizer.mlpackage"),
                                       labelsURL: root.appendingPathComponent("Accent/phoneme_labels.json"), computeUnits: .cpuOnly)
        func synth(_ text: String, rate: Int, name: String) throws -> URL {
            let url = tmp.appendingPathComponent("\(name)-\(rate).wav")
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            task.arguments = ["-v", "Samantha", "-r", String(rate), "-o", url.path,
                              "--file-format=WAVE", "--data-format=LEI16@22050", text]
            try task.run(); task.waitUntilExit()
            guard task.terminationStatus == 0 else { throw NSError(domain: "Synthesis failed", code: 1) }
            return url
        }
        let sentences = [
            "This Thursday three brothers heard that the harbor hotel had a heated pool.",
            "Please sit in this seat and feel the deep heat.",
            "They walked, asked questions, and watched the ships arrive.",
            "Development of a rich vocabulary is necessary, whether you catch each chance or not."
        ]
        var words = 0, newFlags = 0
        for (i, sentence) in sentences.enumerated() {
            let passage = Passage(text: sentence)
            let phones = passage.words.map { Lexicon.phones(for: $0.norm)! }
            for rate in [120, 180, 240] {
                let audio = try synth(sentence, rate: rate, name: "sentence-\(i)")
                guard let aligned = scorer.scoreUtterance(recording: audio, wordPhones: phones) else { fatalError("Alignment failed") }
                var flagged: [String] = []
                for (index, result) in aligned.enumerated() {
                    guard let result else { continue }
                    words += 1
                    if !Lexicon.requiresContext.contains(passage.words[index].norm), result.scores.contains(where: \.needsPractice) {
                        newFlags += 1
                        flagged.append(passage.words[index].norm + ":" + result.scores.filter(\.needsPractice).map { "\($0.arpa)=\(String(format: "%.1f", $0.gop))/\($0.evidenceFrames) heard=\($0.competingIPA ?? "—")" }.joined(separator: ","))
                    }
                }
                print("NATIVE sentence=\(i + 1) rate=\(rate) flagged=\(flagged)")
            }
        }
        var detected = 0, substitutions = 0
        for (spoken, expected) in [("sink", "think"), ("tank", "thank"), ("tree", "three"), ("ship", "sheep"), ("sit", "seat"), ("bed", "bad")] {
            for rate in [140, 200] {
                let audio = try synth(spoken, rate: rate, name: spoken)
                let aligned = scorer.scoreUtterance(recording: audio, wordPhones: [Lexicon.phones(for: expected)!])!
                let flagged = aligned[0]!.scores.contains(where: \.needsPractice)
                substitutions += 1
                if flagged { detected += 1 }
                print("SUBSTITUTION \(spoken)→\(expected) rate=\(rate) detected=\(flagged) scores=\(aligned[0]!.scores.map { "\($0.arpa)=\(String(format: "%.1f", $0.gop))/\($0.evidenceFrames) heard=\($0.competingIPA ?? "—")" })")
            }
        }
        let silence = scorer.score(audio: [Float](repeating: 0, count: 16000), phones: ["TH", "IH1", "NG", "K"])
        guard silence?.contains(where: \.needsPractice) != true else { fatalError("Silence flagged as pronunciation error") }
        print("RESULT: native \(newFlags)/\(words) flagged; substitutions \(detected)/\(substitutions); silence neutral")
        guard newFlags < words / 10, detected >= substitutions / 2 else { fatalError("Audio regression quality gate failed") }
    }
}
