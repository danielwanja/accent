import Foundation

let root = "/Users/danielwanja/GitProjects/accent"
let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("calib", isDirectory: true)
try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
let scorer = try PhonemeScorer(
    modelURL: URL(fileURLWithPath: "\(root)/tools/models/PhonemeRecognizer.mlpackage"),
    labelsURL: URL(fileURLWithPath: "\(root)/tools/models/phoneme_labels.json"))

func synth(_ text: String, rate: Int) -> URL? {
    let url = tmp.appendingPathComponent("\(text.replacingOccurrences(of: " ", with: "_"))-\(rate).wav")
    if !FileManager.default.fileExists(atPath: url.path) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        p.arguments = ["-r", "\(rate)", "-o", url.path, "--file-format=WAVE", "--data-format=LEI16@22050", text]
        try? p.run(); p.waitUntilExit()
        if p.terminationStatus != 0 { return nil }
    }
    return url
}

// (spokenText, targetPhones, focusIndex, label, isError)
let battery: [(String, [String], Int, String, Bool)] = [
    ("think", ["TH","IH1","NG","K"], 0, "θ clean", false),
    ("sink",  ["TH","IH1","NG","K"], 0, "θ←s", true),
    ("tink",  ["TH","IH1","NG","K"], 0, "θ←t", true),
    ("thank", ["TH","AE1","NG","K"], 0, "θ clean", false),
    ("tank",  ["TH","AE1","NG","K"], 0, "θ←t", true),
    ("three", ["TH","R","IY1"], 0, "θ clean", false),
    ("tree",  ["TH","R","IY1"], 0, "θ←t", true),
    ("free",  ["TH","R","IY1"], 0, "θ←f", true),
    ("this",  ["DH","IH1","S"], 0, "ð clean", false),
    ("ziss",  ["DH","IH1","S"], 0, "ð←z", true),
    ("hair",  ["HH","EH1","R"], 0, "h clean", false),
    ("air",   ["HH","EH1","R"], 0, "h dropped", true),
    ("heat",  ["HH","IY1","T"], 0, "h clean", false),
    ("eat",   ["HH","IY1","T"], 0, "h dropped", true),
    ("sheep", ["SH","IY1","P"], 1, "iː clean", false),
    ("ship",  ["SH","IY1","P"], 1, "iː←ɪ", true),
    ("seat",  ["S","IY1","T"], 1, "iː clean", false),
    ("sit",   ["S","IY1","T"], 1, "iː←ɪ", true),
    ("bad",   ["B","AE1","D"], 1, "æ clean", false),
    ("bed",   ["B","AE1","D"], 1, "æ←ɛ", true),
]

var cleanScores: [Double] = []
var errorScores: [Double] = []
for (spoken, phones, focus, label, isError) in battery {
    for rate in [140, 180] {
        guard let wav = synth(spoken, rate: rate),
              let audio = try? PhonemeScorer.loadMono16k(url: wav, start: 0, duration: 10),
              let aligned = scorer.scoreUtterance(recording: wav, wordPhones: [phones]),
              let wa = aligned[0] else { print("SKIP \(spoken)@\(rate)"); continue }
        _ = audio
        let gop = wa.scores[focus].gop
        if isError { errorScores.append(gop) } else { cleanScores.append(gop) }
        print(String(format: "%-6@ vs %-22@ %@  gop=%6.2f", spoken, label, isError ? "ERR " : "OK  ", gop))
    }
}
func stats(_ a: [Double], _ name: String) {
    let s = a.sorted()
    let median = s[s.count/2]
    print(String(format: "%@: n=%d min=%.2f median=%.2f max=%.2f", name, s.count, s.first!, median, s.last!))
}
print("---")
stats(cleanScores, "CLEAN")
stats(errorScores, "ERROR")
