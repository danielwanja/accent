import AVFoundation
import CoreML
import Foundation
import os

/// Tier-2 pronunciation scoring (PLAN.md §3.3): a wav2vec2-base phoneme CTC
/// model (Core ML, on-device) is force-aligned against the word's expected
/// CMUdict phonemes. Peak posterior margins compare the expected sound
/// with a confident competitor, without treating CTC blanks as errors.
/// These are practice signals, not calibrated pronunciation probabilities.
final class PhonemeScorer: @unchecked Sendable {  // immutable after init; MLModel prediction is thread-safe
    struct PhonemeScore: Equatable {
        let arpa: String     // expected phone, stress stripped ("TH")
        let ipa: String      // display form ("θ")
        let gop: Double      // peak log-posterior margin, ≤ 0; needs evidence to interpret
        var evidenceFrames: Int = 0
        var competingIPA: String? = nil
        var isAssessed: Bool {
            guard evidenceFrames > 0, !PhonemeScorer.lowConfidencePhones.contains(arpa) else { return false }
            // A vowel aligned to a neighboring consonant (or vice versa) is
            // suspect timing, not enough evidence for an articulation correction.
            if gop <= -3, let competingIPA {
                return Lexicon.vowels.contains(arpa) == PhonemeScorer.vowelTokens.contains(competingIPA)
            }
            return true
        }
        /// Require a confident competing sound before offering correction.
        var needsPractice: Bool {
            isAssessed && gop <= -3 && competingIPA != nil

        }
        var stressed: Bool = false   // carries the word's primary stress
    }

    /// Lexical stress check for a multi-syllable word: which syllable the
    /// speaker made prominent (energy × duration over aligned frames) vs the
    /// one the lexicon stresses. Indexes count vowels, 0-based.
    struct StressCheck: Equatable {
        let expectedSyllable: Int
        let detectedSyllable: Int
        let syllableCount: Int
        var ok: Bool { expectedSyllable == detectedSyllable }
    }

    /// Phones whose GOP the model can't judge reliably (same battery: clean
    /// "hair" scored -5 while dropped-h "air" scored 0 — breathy vowel
    /// onsets and /h/ are acoustically interchangeable to it). They never
    /// drive word verdicts or colored sound chips.
    static let lowConfidencePhones: Set<String> = ["HH"]
    private static let vowelTokens: Set<String> = Set(
        Lexicon.vowels.flatMap { modelTokens(forArpa: $0) } + ["ə", "ɪə", "eə", "ʊə"])

    // MARK: - Background loading
    //
    // First load on a device includes Core ML compute-graph specialization
    // and can take a long time. Nothing may block on it: `ready` returns nil
    // until the load finishes (takes before that show recognition only).

    private static let readyBox = OSAllocatedUnfairLock<PhonemeScorer?>(initialState: nil)

    /// Staged load: CPU-only first — it skips ANE/GPU graph specialization,
    /// so it's available in seconds and always works. Then try the faster
    /// compute units in the background (their first-time specialization can
    /// take minutes on device, and the ANE path can fail outright) and swap
    /// them in only after a warm-up prediction proves them.
    private static let loadTask: Task<PhonemeScorer?, Never> = Task.detached(priority: .userInitiated) {
        guard let modelURL = Bundle.main.url(forResource: "PhonemeRecognizer", withExtension: "mlmodelc")
            ?? Bundle.main.url(forResource: "PhonemeRecognizer", withExtension: "mlpackage"),
              let labelsURL = Bundle.main.url(forResource: "phoneme_labels", withExtension: "json") else {
            print("ACCENT phoneme scorer UNAVAILABLE: model not bundled")
            return nil
        }
        let probe = (0..<4800).map { Float(sin(Double($0) * 0.08)) * 0.01 }
        let started = Date()
        var current: PhonemeScorer?
        if let cpu = try? PhonemeScorer(modelURL: modelURL, labelsURL: labelsURL, computeUnits: .cpuOnly),
           cpu.logPosteriors(audio: probe) != nil {
            readyBox.withLock { $0 = cpu }
            current = cpu
            print("ACCENT phoneme scorer ready (CPU) after \(Int(-started.timeIntervalSinceNow))s")
        } else {
            print("ACCENT phoneme scorer: CPU load failed")
        }
        for units in [MLComputeUnits.all, .cpuAndGPU] {
            let stage = Date()
            if let fast = try? PhonemeScorer(modelURL: modelURL, labelsURL: labelsURL, computeUnits: units),
               fast.logPosteriors(audio: probe) != nil {
                readyBox.withLock { $0 = fast }
                current = fast
                print("ACCENT phoneme scorer upgraded (units \(units.rawValue)) after \(Int(-stage.timeIntervalSinceNow))s")
                break
            }
            print("ACCENT phoneme scorer: units \(units.rawValue) unavailable")
        }
        return current
    }

    /// Non-blocking: nil until at least the CPU load completes.
    static var ready: PhonemeScorer? { readyBox.withLock { $0 } }

    /// Awaitable load, for callers that can wait (the word detail card).
    /// Note this waits for the full staged load; prefer `ready` when non-nil.
    static func loaded() async -> PhonemeScorer? { await loadTask.value }

    /// Kick the background load without waiting.
    static func beginLoading() { _ = loadTask }

    struct Labels: Decodable {
        let sample_rate: Double
        let do_normalize: Bool
        let pad_token_id: Int
        let labels: [String]
    }

    private let model: MLModel
    private let labels: Labels
    private let blankID: Int
    /// IPA token → class id.
    private let tokenID: [String: Int]
    /// Class ids that are real phones (competitors for the GOP margin).
    private let phoneIDs: [Int]

    init(modelURL: URL, labelsURL: URL, computeUnits: MLComputeUnits = .all) throws {
        let config = MLModelConfiguration()
        config.computeUnits = computeUnits
        // .mlpackage needs compiling first; .mlmodelc loads directly.
        let compiled = modelURL.pathExtension == "mlmodelc"
            ? modelURL
            : try MLModel.compileModel(at: modelURL)
        model = try MLModel(contentsOf: compiled, configuration: config)
        labels = try JSONDecoder().decode(Labels.self, from: Data(contentsOf: labelsURL))
        blankID = labels.pad_token_id
        var ids: [String: Int] = [:]
        var phones: [Int] = []
        for (id, token) in labels.labels.enumerated() {
            ids[token] = id
            if !["[PAD]", "[UNK]", " ", "|", "<s>", "</s>"].contains(token) {
                phones.append(id)
            }
        }
        tokenID = ids
        phoneIDs = phones
    }

    // MARK: - ARPAbet → model tokens

    /// Acceptable model tokens per ARPAbet phone (with stress digit). First
    /// entry is canonical; extras are fine allophones (flapped/glottal t,
    /// British oʊ) that shouldn't be punished.
    static func modelTokens(forArpa phone: String) -> [String] {
        let stress = phone.last?.isNumber == true ? phone.suffix(1) : ""
        let base = phone.filter { !$0.isNumber }
        switch base {
        case "AA": return ["ɑ", "ɔ"]
        case "AE": return ["æ"]
        case "AH": return stress == "0" ? ["ə", "ʌ"] : ["ʌ", "ə"]
        case "AO": return ["ɔ", "ɑ"]
        case "AW": return ["aʊ"]
        case "AY": return ["aɪ"]
        case "B": return ["b"]
        case "CH": return ["t͡ʃ"]
        case "D": return ["d", "ɾ"]
        case "DH": return ["ð"]
        case "EH": return ["ɛ"]
        case "ER": return ["ɝ"]
        case "EY": return ["eɪ"]
        case "F": return ["f"]
        case "G": return ["ɡ"]
        case "HH": return ["h"]
        case "IH": return stress == "0" ? ["ɪ", "ə"] : ["ɪ"]
        case "IY": return stress == "0" ? ["i", "ɪ"] : ["i"]
        case "JH": return ["d͡ʒ"]
        case "K": return ["k"]
        case "L": return ["l"]
        case "M": return ["m"]
        case "N": return ["n"]
        case "NG": return ["ŋ"]
        case "OW": return ["oʊ", "əʊ"]
        case "OY": return ["ɔɪ"]
        case "P": return ["p"]
        case "R": return ["ɹ"]
        case "S": return ["s"]
        case "SH": return ["ʃ"]
        case "T": return ["t", "ɾ", "ʔ"]
        case "TH": return ["θ"]
        case "UH": return ["ʊ"]
        case "UW": return ["u"]
        case "V": return ["v"]
        case "W": return ["w"]
        case "Y": return ["j"]
        case "Z": return ["z"]
        case "ZH": return ["ʒ"]
        default: return []
        }
    }

    // MARK: - Whole-take forced alignment

    struct WordAlignment {
        let start: TimeInterval      // in the recording's timeline
        let duration: TimeInterval
        let scores: [PhonemeScore]
        let stress: StressCheck?     // multi-syllable words with a marked stress
    }

    /// wav2vec2's frame stride: 320 samples at 16 kHz.
    private static let frameDuration = 0.02

    /// One pass over a bounded audio window: align the transcript phone sequence
    /// of every read word against the full recording. Yields per-word
    /// boundaries at 20 ms precision — the recognizer's word timestamps are
    /// recognition times, not phonetic boundaries, and cut into neighbors —
    /// plus per-phoneme evidence from the same alignment. Entries with empty
    /// phone lists (out-of-lexicon words) come back nil.
    func scoreUtterance(recording: URL, wordPhones: [[String]], start: TimeInterval = 0, duration: TimeInterval = 20) -> [WordAlignment?]? {
        guard wordPhones.contains(where: { !$0.isEmpty }) else { return nil }
        guard let audio = try? Self.loadMono16k(url: recording, start: start, duration: duration),
              audio.count >= 1600 else { return nil }

        var flat: [[Int]] = []
        var owner: [Int] = []            // phone position → word index
        var phoneLabel: [String] = []    // original phone, stress digit kept
        for (wordIndex, phones) in wordPhones.enumerated() {
            for phone in phones {
                let ids = Self.modelTokens(forArpa: phone).compactMap { tokenID[$0] }
                guard !ids.isEmpty else { continue }
                flat.append(ids)
                owner.append(wordIndex)
                phoneLabel.append(phone)
            }
        }
        guard !flat.isEmpty,
              let logProbs = logPosteriors(audio: audio),
              logProbs.count >= flat.count,
              let assignment = Self.align(logProbs: logProbs, candidates: flat, blankID: blankID) else {
            return nil
        }

        // Per-frame RMS energy for stress prominence (frame stride 320,
        // window 400 — wav2vec2's receptive geometry, roughly).
        var rms = [Double](repeating: 0, count: logProbs.count)
        for frame in rms.indices {
            let lo = frame * 320
            let hi = min(lo + 400, audio.count)
            guard lo < hi else { break }
            var sum = 0.0
            for i in lo..<hi { sum += Double(audio[i]) * Double(audio[i]) }
            rms[frame] = (sum / Double(hi - lo)).squareRoot()
        }

        var scores = [[PhonemeScore]](repeating: [], count: wordPhones.count)
        var firstFrame = [Int](repeating: .max, count: wordPhones.count)
        var lastFrame = [Int](repeating: -1, count: wordPhones.count)
        // Per word: (isStressed, prominence) for each vowel, in order.
        var vowelProminence = [[(stressed: Bool, prominence: Double)]](repeating: [], count: wordPhones.count)
        for (position, frames) in assignment.enumerated() {
            let wordIndex = owner[position]
            let ids = flat[position]
            var energySum = 0.0
            for frame in frames {
                energySum += rms[frame]
                firstFrame[wordIndex] = min(firstFrame[wordIndex], frame)
                lastFrame[wordIndex] = max(lastFrame[wordIndex], frame)
            }
            let phone = phoneLabel[position]
            let base = phone.filter { !$0.isNumber }
            var evidence = acousticScore(phone: phone, frames: Self.evidenceWindow(at: position, assignment: assignment, frameCount: logProbs.count), ids: ids, logProbs: logProbs)
            evidence.stressed = phone.hasSuffix("1")
            scores[wordIndex].append(evidence)
            if Lexicon.vowels.contains(base) {
                // Prominence = total energy over the vowel's frames — louder
                // AND longer both push it up, which is what stress is.
                vowelProminence[wordIndex].append((phone.hasSuffix("1"), energySum))
            }
        }

        return wordPhones.indices.map { wordIndex in
            guard lastFrame[wordIndex] >= 0 else { return nil }
            let wordStart = start + Double(firstFrame[wordIndex]) * Self.frameDuration
            let end = start + Double(lastFrame[wordIndex] + 1) * Self.frameDuration

            var stress: StressCheck?
            let vowels = vowelProminence[wordIndex]
            if vowels.count >= 2, let expected = vowels.firstIndex(where: \.stressed) {
                let detected = vowels.indices.max { vowels[$0].prominence < vowels[$1].prominence } ?? expected
                // Close calls go to the speaker: only flag a clear shift.
                let clear = vowels[detected].prominence > vowels[expected].prominence * 1.25
                stress = StressCheck(
                    expectedSyllable: expected,
                    detectedSyllable: (detected == expected || !clear) ? expected : detected,
                    syllableCount: vowels.count)
            }
            return WordAlignment(
                start: wordStart, duration: end - wordStart,
                scores: scores[wordIndex], stress: stress)
        }
    }

    // MARK: - Scoring

    /// Score a word slice of the session recording against its expected
    /// phonemes. Returns nil when the word is out-of-lexicon, the audio can't
    /// be read, or alignment fails.
    func score(wordNorm: String, recording: URL, start: TimeInterval, duration: TimeInterval, estimatedTiming: Bool = false) -> [PhonemeScore]? {
        guard let phones = Lexicon.phones(for: wordNorm) else { return nil }
        // Estimated boundaries (apportioned multi-word chunks) get a wider
        // window; CTC alignment tolerates leading/trailing context.
        let pad = estimatedTiming ? 0.3 : 0.12
        guard let audio = try? Self.loadMono16k(
            url: recording, start: max(0, start - pad), duration: duration + 2 * pad) else { return nil }
        return score(audio: audio, phones: phones)
    }

    /// Score raw 16 kHz mono audio against an expected ARPAbet sequence.
    func score(audio: [Float], phones: [String]) -> [PhonemeScore]? {
        guard !phones.isEmpty, audio.count >= 1600 else { return nil }

        // Per-phone candidate class ids.
        let candidates: [[Int]] = phones.map { phone in
            Self.modelTokens(forArpa: phone).compactMap { tokenID[$0] }
        }
        guard candidates.allSatisfy({ !$0.isEmpty }) else { return nil }

        guard let logProbs = logPosteriors(audio: audio) else { return nil }
        let frames = logProbs.count
        guard frames >= phones.count else { return nil }

        guard let assignment = Self.align(
            logProbs: logProbs, candidates: candidates, blankID: blankID) else { return nil }

        return phones.enumerated().map { index, phone in
            acousticScore(phone: phone, frames: Self.evidenceWindow(at: index, assignment: assignment, frameCount: logProbs.count), ids: candidates[index], logProbs: logProbs)
        }
    }

    /// Include the blank interval around each aligned phone. CTC commonly
    /// emits a real sound on just ONE frame; counting frames penalizes fast
    /// speech, while forced frames alone can miss a substituted consonant.
    static func evidenceWindow(at index: Int, assignment: [[Int]], frameCount: Int) -> [Int] {
        guard let first = assignment[index].first, let last = assignment[index].last else { return [] }
        let lower = index == 0 ? 0 : ((assignment[index - 1].last ?? first) + first) / 2 + 1
        let upper = index + 1 == assignment.count ? frameCount : (last + (assignment[index + 1].first ?? last)) / 2 + 1
        return Array(max(0, lower)..<min(frameCount, max(lower, upper)))
    }

    /// Compare posterior peaks, rather than averaging blank-dominated frames.
    /// A strong expected peak wins even if nearby transition frames differ.
    private func acousticScore(phone: String, frames: [Int], ids: [Int], logProbs: [[Double]]) -> PhonemeScore {
        var targetPeak = -Double.infinity
        var bestPeak = -Double.infinity
        var competitor: Int?
        var evidenceFrames = 0
        for frame in frames {
            let row = logProbs[frame]
            targetPeak = max(targetPeak, ids.map { row[$0] }.max() ?? -.infinity)
            guard let best = phoneIDs.max(by: { row[$0] < row[$1] }) else { continue }
            // Blank probability measures CTC emission timing, not pronunciation
            // quality. Require both real acoustic mass and a clear phone winner.
            let phoneMass = phoneIDs.reduce(0.0) { $0 + exp(row[$1]) }
            guard row[best] >= log(0.1), exp(row[best]) / max(phoneMass, 1e-12) >= 0.8 else { continue }
            evidenceFrames += 1
            if row[best] > bestPeak {
                bestPeak = row[best]
                competitor = ids.contains(best) ? nil : best
            }
        }
        let margin = bestPeak.isFinite ? min(0, targetPeak - bestPeak) : 0
        return PhonemeScore(arpa: phone.filter { !$0.isNumber }, ipa: Lexicon.ipa(forPhone: phone),
                            gop: margin, evidenceFrames: evidenceFrames,
                            competingIPA: competitor.map { labels.labels[$0] })
    }

    /// Run the model and return per-frame log-softmax rows.
    private func logPosteriors(audio: [Float]) -> [[Double]]? {
        guard !audio.isEmpty, audio.allSatisfy(\.isFinite),
              audio.reduce(0.0, { $0 + Double($1) * Double($1) }) / Double(audio.count) > 1e-6 else { return nil }
        var samples = audio
        if labels.do_normalize {
            let mean = samples.reduce(0, +) / Float(samples.count)
            let variance = samples.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Float(samples.count)
            let scale = 1 / (variance + 1e-7).squareRoot()
            samples = samples.map { ($0 - mean) * scale }
        }
        guard let array = try? MLMultiArray(shape: [1, NSNumber(value: samples.count)], dataType: .float32) else { return nil }
        samples.withUnsafeBufferPointer { src in
            array.dataPointer.assumingMemoryBound(to: Float.self)
                .update(from: src.baseAddress!, count: samples.count)
        }
        guard let input = try? MLDictionaryFeatureProvider(dictionary: ["audio": array]),
              let output = try? model.prediction(from: input),
              let logits = output.featureValue(for: "logits")?.multiArrayValue else { return nil }

        let frames = logits.shape[1].intValue
        let classes = logits.shape[2].intValue
        let ptr = logits.dataPointer.assumingMemoryBound(to: Float.self)
        var rows = [[Double]](repeating: [Double](repeating: 0, count: classes), count: frames)
        for t in 0..<frames {
            var maxV = -Float.infinity
            for c in 0..<classes { maxV = max(maxV, ptr[t * classes + c]) }
            var sumExp = 0.0
            for c in 0..<classes { sumExp += exp(Double(ptr[t * classes + c] - maxV)) }
            let logSum = log(sumExp) + Double(maxV)
            for c in 0..<classes { rows[t][c] = Double(ptr[t * classes + c]) - logSum }
        }
        return rows
    }

    /// CTC Viterbi forced alignment. Returns, per phone, the frames assigned
    /// to it. States alternate blank/phone: [b, p0, b, p1, …, b].
    static func align(logProbs: [[Double]], candidates: [[Int]], blankID: Int) -> [[Int]]? {
        guard !logProbs.isEmpty, !candidates.isEmpty,
              candidates.allSatisfy({ !$0.isEmpty }),
              logProbs.allSatisfy({ row in
                  row.indices.contains(blankID) && candidates.joined().allSatisfy { row.indices.contains($0) }
              }) else { return nil }
        let frameCount = logProbs.count
        let phoneCount = candidates.count
        let stateCount = 2 * phoneCount + 1
        let neg = -Double.infinity

        @inline(__always) func emit(_ state: Int, _ frame: Int) -> Double {
            if state % 2 == 0 { return logProbs[frame][blankID] }
            let ids = candidates[(state - 1) / 2]
            return ids.map { logProbs[frame][$0] }.max() ?? neg
        }

        var score = [[Double]](repeating: [Double](repeating: neg, count: stateCount), count: frameCount)
        var back = [[Int]](repeating: [Int](repeating: 0, count: stateCount), count: frameCount)
        score[0][0] = emit(0, 0)
        if stateCount > 1 { score[0][1] = emit(1, 0); back[0][1] = 1 }

        for t in 1..<frameCount {
            for s in 0..<stateCount {
                var bestPrev = score[t - 1][s]
                var bestState = s
                if s >= 1, score[t - 1][s - 1] > bestPrev {
                    bestPrev = score[t - 1][s - 1]; bestState = s - 1
                }
                // Skip a blank between two phones only when they differ.
                if s >= 2, s % 2 == 1 {
                    let prevPhone = candidates[(s - 3) / 2]
                    let thisPhone = candidates[(s - 1) / 2]
                    if prevPhone != thisPhone, score[t - 1][s - 2] > bestPrev {
                        bestPrev = score[t - 1][s - 2]; bestState = s - 2
                    }
                }
                score[t][s] = bestPrev == neg ? neg : bestPrev + emit(s, t)
                back[t][s] = bestState
            }
        }

        let lastStates = stateCount >= 2 ? [stateCount - 1, stateCount - 2] : [stateCount - 1]
        guard var state = lastStates.max(by: { score[frameCount - 1][$0] < score[frameCount - 1][$1] }),
              score[frameCount - 1][state] > neg else { return nil }

        var assignment = [[Int]](repeating: [], count: phoneCount)
        for t in stride(from: frameCount - 1, through: 0, by: -1) {
            if state % 2 == 1 { assignment[(state - 1) / 2].append(t) }
            if t > 0 { state = back[t][state] }
        }
        for index in assignment.indices { assignment[index].reverse() }
        return assignment
    }

    // MARK: - Audio loading

    /// Read a slice of an audio file and resample to 16 kHz mono Float32.
    static func loadMono16k(url: URL, start: TimeInterval, duration: TimeInterval) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let sourceFormat = file.processingFormat
        let sourceRate = sourceFormat.sampleRate
        guard start.isFinite, duration.isFinite, duration > 0, sourceRate > 0,
              max(0, start) < Double(file.length) / sourceRate else {
            throw NSError(domain: "PhonemeScorer", code: 1)
        }
        let startFrame = AVAudioFramePosition(max(0, start) * sourceRate)
        let frameCount = AVAudioFrameCount(min(
            Double(file.length - startFrame),
            duration * sourceRate))
        guard frameCount > 0,
              let inBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount) else {
            throw NSError(domain: "PhonemeScorer", code: 1)
        }
        file.framePosition = startFrame
        try file.read(into: inBuffer, frameCount: frameCount)

        guard let outFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: sourceFormat, to: outFormat) else {
            throw NSError(domain: "PhonemeScorer", code: 2)
        }
        let outCapacity = AVAudioFrameCount(Double(frameCount) * 16000 / sourceRate) + 16
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: outCapacity) else {
            throw NSError(domain: "PhonemeScorer", code: 3)
        }
        var fed = false
        var convError: NSError?
        converter.convert(to: outBuffer, error: &convError) { _, status in
            if fed { status.pointee = .endOfStream; return nil }
            fed = true
            status.pointee = .haveData
            return inBuffer
        }
        if let convError { throw convError }
        let n = Int(outBuffer.frameLength)
        guard let data = outBuffer.floatChannelData?[0] else {
            throw NSError(domain: "PhonemeScorer", code: 4)
        }
        return Array(UnsafeBufferPointer(start: data, count: n))
    }
}
