import Foundation

/// One entry in the French → American English issue map (PLAN.md §4):
/// a residual accent feature, why it happens, and how to coach it.
struct Issue: Identifiable, Hashable {
    let id: String
    let name: String        // short display name, e.g. "TH"
    let phonemes: String    // IPA, e.g. "/θ/ /ð/"
    let why: String         // L1 interference explanation
    let cue: String         // articulation tip
    let minimalPairs: [String]
    let drillTitle: String
    let drillText: String   // fallback practice passage when the LLM is unavailable
}

/// Curated taxonomy + heuristic word→issue mapping.
///
/// v1 maps by spelling patterns (a G2P-lite). It over-attributes on purpose —
/// aggregate stats stay comparative — and is structured so a real lexicon
/// (CMUdict) can replace `issues(for:)` in M3 without touching callers.
enum Phonics {
    static let issues: [Issue] = [
        Issue(
            id: "th", name: "TH", phonemes: "/θ/ /ð/",
            why: "French has no dental fricatives, so /θ/ slides to [s] or [t] and /ð/ to [z] or [d] — think/sink, this/zis.",
            cue: "Tongue tip between the teeth, air flowing. /θ/ has no voice; /ð/ buzzes.",
            minimalPairs: ["think · sink", "this · zis", "three · tree", "thank · tank"],
            drillTitle: "TH Drill",
            drillText: "Thirty-three thankful brothers thought this thing through. Whether they gather there or not, the truth is worth their breath."),
        Issue(
            id: "h", name: "H", phonemes: "/h/",
            why: "French /h/ is silent, so English h gets dropped — or added where it doesn't belong (hypercorrection): air/hair, old/hold.",
            cue: "A small puff of breath before the vowel, like fogging a mirror.",
            minimalPairs: ["air · hair", "old · hold", "eat · heat", "ill · hill"],
            drillTitle: "H Drill",
            drillText: "How high can Henry hop? He held his hat and hurried home, happy to hear her hum in the hallway."),
        Issue(
            id: "ih-ee", name: "I vs EE", phonemes: "/ɪ/ /iː/",
            why: "French has one high front vowel, so ship and sheep collapse together — /ɪ/ is shorter, laxer, lower than /iː/.",
            cue: "For /ɪ/ relax the tongue and keep it short: ship, sit, live. For /iː/ smile and stretch: sheep, seat, leave.",
            minimalPairs: ["ship · sheep", "live · leave", "sit · seat", "fill · feel"],
            drillTitle: "Ship & Sheep Drill",
            drillText: "Did the ship slip in the deep sea? Please sit in this seat, eat these chips, and feel the heat leave the little green field."),
        Issue(
            id: "r", name: "R", phonemes: "/ɹ/",
            why: "The French uvular [ʁ] lives in the throat; American /ɹ/ curls the tongue tip back without touching anything.",
            cue: "Tongue tip up and back, sides against the upper molars, nothing touches the roof.",
            minimalPairs: ["red · head", "rock · lock", "right · light", "arrive · alive"],
            drillTitle: "R Drill",
            drillText: "Robert readily carried three red barrels around the rural road. Her brother's rare error truly worried our friend."),
        Issue(
            id: "stress", name: "Stress", phonemes: "ˈ · ə",
            why: "French pushes stress to the last syllable; English stress is lexical — deVELopment, not developMENT — and unstressed vowels reduce to schwa.",
            cue: "Find the strong syllable, punch it, and let the others shrink to 'uh'.",
            minimalPairs: ["DEvelop · deVELopment", "PHOtograph · phoTOgraphy", "ECOnomy · ecoNOmic"],
            drillTitle: "Stress Drill",
            drillText: "The development of comfortable photography is a necessary ability. Biology, technology, and economics carry their emphasis in particular places."),
        Issue(
            id: "ed", name: "-ED", phonemes: "/t/ /d/ /ɪd/",
            why: "The -ed ending has three sounds: walked /t/, played /d/, wanted /ɪd/ — French speakers tend to voice or syllabify all of them.",
            cue: "After a voiceless sound say /t/, after a voiced one /d/; only t and d themselves earn the extra /ɪd/ syllable.",
            minimalPairs: ["walked · walk-ed", "played · play-ed", "wanted · want-ed"],
            drillTitle: "-ED Drill",
            drillText: "She walked, talked, and laughed, then played and stayed. He wanted, needed, and decided — and finally rested."),
        Issue(
            id: "ch-sh", name: "CH vs SH", phonemes: "/tʃ/ /ʃ/ /dʒ/ /ʒ/",
            why: "French /ʃ/ and /ʒ/ exist, but the English affricates add a t or d in front: chair starts with a tiny t, joke with a tiny d.",
            cue: "For ch and j, touch the ridge first, then release into the hiss — a stop plus a fricative.",
            minimalPairs: ["chair · share", "cheap · sheep", "joke · yoke", "catch · cash"],
            drillTitle: "CH Drill",
            drillText: "Charles chose a cheap chair to share. The children cheerfully chanted while John jotted a joke about the jelly."),
        Issue(
            id: "vowel-ae", name: "A vowels", phonemes: "/æ/ /ɛ/ /ʌ/",
            why: "The bad/bed contrast doesn't exist in French — /æ/ needs a wider jaw than any French vowel, and /ʌ/ tends to round.",
            cue: "For /æ/ drop the jaw like a doctor's 'ahh' but front: bad, hat, gather.",
            minimalPairs: ["bad · bed", "hat · het", "cat · cut", "match · much"],
            drillTitle: "Vowel Drill",
            drillText: "The bad cat sat on that black hat. Dad had a snack and began to laugh at the mad match."),
        Issue(
            id: "clusters", name: "Clusters", phonemes: "CC(C)",
            why: "French syllables end simply; English piles consonants at the end — months, asked, texts — and the cluster tends to lose a member.",
            cue: "Say every consonant, quickly but fully: mon-th-s, as-k-t.",
            minimalPairs: ["months · monts", "asked · ast", "texts · tex"],
            drillTitle: "Cluster Drill",
            drillText: "He asked about the texts he sent last month. Six masked guests grasped the facts and risked the worst."),
        Issue(
            id: "linking", name: "Linking", phonemes: "‿",
            why: "English glues words together — turn it off becomes tur-ni-toff — while French keeps an even, syllable-timed rhythm. Silent letters (comb, receipt) add traps.",
            cue: "Let the final consonant start the next word. Aim for a long-short galloping rhythm, not a metronome.",
            minimalPairs: ["turn it off · turn-it-off", "an apple · a-napple"],
            drillTitle: "Linking Drill",
            drillText: "Turn it off and hand it over. Pick it up, put it on, and read it out in an even tone."),
    ]

    static func issue(_ id: String) -> Issue? {
        issues.first { $0.id == id }
    }

    /// Issue ids a single phoneme (stress-stripped ARPAbet) belongs to —
    /// the phone-level issues only; ed/clusters/stress/linking stay word-level.
    static func issueIDs(forPhone base: String) -> [String] {
        switch base {
        case "TH", "DH": return ["th"]
        case "HH": return ["h"]
        case "IH", "IY": return ["ih-ee"]
        case "R", "ER": return ["r"]
        case "CH", "JH", "SH", "ZH": return ["ch-sh"]
        case "AE", "EH", "AH": return ["vowel-ae"]
        default: return []
        }
    }

    /// Issue ids a word exercises. Prefers the real phoneme sequence from the
    /// lexicon; falls back to spelling heuristics for out-of-lexicon words.
    static func issueIDs(for norm: String) -> [String] {
        if let fromLexicon = Lexicon.issueIDs(for: norm) {
            return fromLexicon
        }
        return spellingIssueIDs(for: norm)
    }

    /// Spelling-pattern fallback (G2P-lite) for words CMUdict doesn't know.
    static func spellingIssueIDs(for norm: String) -> [String] {
        var found: [String] = []
        if norm.contains("th") { found.append("th") }
        if norm.hasPrefix("h") { found.append("h") }
        if norm.contains("ee") || norm.contains("ea") || shortIPattern(norm) { found.append("ih-ee") }
        if norm.contains("r") { found.append("r") }
        if syllableEstimate(norm) >= 3 { found.append("stress") }
        if norm.hasSuffix("ed") && norm.count > 3 { found.append("ed") }
        if norm.contains("ch") || norm.contains("sh") || norm.hasPrefix("j") || norm.hasSuffix("dge") { found.append("ch-sh") }
        if shortAPattern(norm) { found.append("vowel-ae") }
        if endsInCluster(norm) { found.append("clusters") }
        return found
    }

    /// Rough syllable count: groups of consecutive vowel letters.
    static func syllableEstimate(_ norm: String) -> Int {
        var count = 0
        var inVowelRun = false
        for ch in norm {
            let isVowel = "aeiouy".contains(ch)
            if isVowel && !inVowelRun { count += 1 }
            inVowelRun = isVowel
        }
        // Silent final e: "close" is one syllable, not two.
        if norm.hasSuffix("e") && !norm.hasSuffix("le") && count > 1 { count -= 1 }
        return max(count, 1)
    }

    private static func shortIPattern(_ norm: String) -> Bool {
        // One-syllable words with a lone short i: ship, sit, live, trip.
        guard syllableEstimate(norm) == 1, norm.contains("i"), !norm.contains("igh") else { return false }
        return !norm.contains("ie") && !norm.contains("ai") && !norm.contains("oi") && !norm.contains("ei")
    }

    private static func shortAPattern(_ norm: String) -> Bool {
        // One-syllable words with a lone short a: bad, hat, match.
        guard syllableEstimate(norm) == 1, norm.contains("a") else { return false }
        return !norm.contains("ai") && !norm.contains("au") && !norm.contains("aw")
            && !norm.contains("ay") && !norm.contains("ar") && !norm.hasSuffix("a")
    }

    private static func endsInCluster(_ norm: String) -> Bool {
        let consonants = Set("bcdfghjklmnpqstvwxz")  // r and y act vowel-ish at word end
        // The -ed spelling hides clusters: asked is /æskt/, walked /wɔːkt/.
        let effective = norm.hasSuffix("ed") ? String(norm.dropLast(2)) + "d" : norm
        let tail = effective.suffix(3)
        var run = 0
        for ch in tail.reversed() {
            if consonants.contains(ch) { run += 1 } else { break }
        }
        return run >= 2
    }
}
