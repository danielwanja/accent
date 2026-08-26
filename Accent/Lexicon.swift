import Foundation

/// CMUdict-backed pronunciation lexicon (bundled, primary pronunciations only).
/// Phones are ARPAbet with stress digits on vowels: "TH IH1 NG K".
enum Lexicon {
    /// word (lowercase) → phones. ~126k entries, loaded once on first use
    /// (~3 MB text; a beat of startup cost on a background thread).
    private static let entries: [String: [String]] = {
        guard let url = Bundle.main.url(forResource: "cmudict", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            print("ACCENT lexicon missing from bundle")
            return [:]
        }
        var dict = [String: [String]](minimumCapacity: 130_000)
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ")
            guard parts.count > 1 else { continue }
            dict[String(parts[0])] = parts.dropFirst().map(String.init)
        }
        return dict
    }()

    /// Kick off the load without blocking the caller.
    static func warmUp() {
        DispatchQueue.global(qos: .utility).async {
            #if DEBUG
            print("ACCENT lexicon: \(entries.count) words, think=/\(ipa(for: "think") ?? "?")/, whether→\(issueIDs(for: "whether") ?? [])")
            #endif
        }
    }

    /// ARPAbet phones (with stress digits) for a normalized word.
    static func phones(for norm: String) -> [String]? {
        entries[norm]
    }

    /// Phones with stress digits stripped: "TH IH NG K".
    static func bases(for norm: String) -> [String]? {
        phones(for: norm)?.map { $0.filter { !$0.isNumber } }
    }

    /// Display form in IPA, stress marks included: "ˈθɪŋk".
    static func ipa(for norm: String) -> String? {
        guard let phones = phones(for: norm) else { return nil }
        var out = ""
        for phone in phones {
            if phone.hasSuffix("1") { out += "ˈ" }
            else if phone.hasSuffix("2") { out += "ˌ" }
            out += ipa(forPhone: phone)
        }
        return out
    }

    /// Display form of one phone, stress-aware: AH0 is schwa.
    static func ipa(forPhone phone: String) -> String {
        let base = phone.filter { !$0.isNumber }
        if base == "AH", phone.hasSuffix("0") { return "ə" }
        return arpaToIPA[base] ?? base.lowercased()
    }

    static let arpaToIPA: [String: String] = [
        "AA": "ɑ", "AE": "æ", "AH": "ʌ", "AO": "ɔ", "AW": "aʊ", "AY": "aɪ",
        "B": "b", "CH": "tʃ", "D": "d", "DH": "ð", "EH": "ɛ", "ER": "ɚ",
        "EY": "eɪ", "F": "f", "G": "ɡ", "HH": "h", "IH": "ɪ", "IY": "iː",
        "JH": "dʒ", "K": "k", "L": "l", "M": "m", "N": "n", "NG": "ŋ",
        "OW": "oʊ", "OY": "ɔɪ", "P": "p", "R": "ɹ", "S": "s", "SH": "ʃ",
        "T": "t", "TH": "θ", "UH": "ʊ", "UW": "uː", "V": "v", "W": "w",
        "Y": "j", "Z": "z", "ZH": "ʒ",
    ]

    private static let vowels: Set<String> = [
        "AA", "AE", "AH", "AO", "AW", "AY", "EH", "ER", "EY",
        "IH", "IY", "OW", "OY", "UH", "UW",
    ]

    /// Issue ids a word exercises, judged from its real phoneme sequence.
    /// Returns nil for out-of-lexicon words (caller falls back to spelling).
    static func issueIDs(for norm: String) -> [String]? {
        guard let phones = phones(for: norm) else { return nil }
        let bases = phones.map { $0.filter { !$0.isNumber } }
        var found: [String] = []
        if bases.contains("TH") || bases.contains("DH") { found.append("th") }
        if bases.first == "HH" { found.append("h") }
        if bases.contains("IH") || bases.contains("IY") { found.append("ih-ee") }
        if bases.contains("R") || bases.contains("ER") { found.append("r") }
        let syllables = bases.filter { vowels.contains($0) || $0 == "ER" }.count
        if syllables >= 3 { found.append("stress") }
        if norm.hasSuffix("ed") && norm.count > 3,
           let last = bases.last, last == "T" || last == "D" { found.append("ed") }
        if bases.contains(where: { ["CH", "JH", "SH", "ZH"].contains($0) }) { found.append("ch-sh") }
        if bases.contains("AE") || bases.contains("EH") || bases.contains("AH") { found.append("vowel-ae") }
        var trailingConsonants = 0
        for base in bases.reversed() {
            if vowels.contains(base) || base == "ER" { break }
            trailingConsonants += 1
        }
        if trailingConsonants >= 2 { found.append("clusters") }
        return found
    }
}
