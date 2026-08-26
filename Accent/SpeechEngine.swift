import AVFoundation
import Speech

enum SpeechEngineError: LocalizedError {
    case microphoneDenied
    case speechDenied
    case localeUnsupported
    case notPrepared

    var errorDescription: String? {
        switch self {
        case .microphoneDenied: return "Microphone access was denied. Enable it in Settings."
        case .speechDenied: return "Speech recognition access was denied. Enable it in Settings."
        case .localeUnsupported: return "English transcription isn't available on this device."
        case .notPrepared: return "Speech engine wasn't prepared before starting."
        }
    }
}

/// Captures mic audio and emits live transcript updates.
///
/// Prefers the iOS 26 SpeechAnalyzer pipeline (fully on-device, word timings).
/// Falls back to SFSpeechRecognizer where the analyzer's model assets aren't
/// available — notably the simulator. The fallback also matters later: it is
/// the API that exposes per-word confidence for tier-1 scoring.
final class SpeechEngine {
    /// Both backends reduce to the same shape: non-final updates replace the
    /// current in-flight hypothesis segment; final updates commit it. SFSpeech
    /// restarts its hypothesis after each finalized utterance, so finals must
    /// be accumulated, never replaced.
    struct Update {
        let words: [TimedWord]
        let isFinal: Bool
    }

    private enum Backend {
        case analyzer
        case legacy
    }

    private let locale = Locale(identifier: "en_US")
    private let audioEngine = AVAudioEngine()
    private var backend: Backend?

    // SpeechAnalyzer path
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var analyzerFormat: AVAudioFormat?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var recognizerTask: Task<Void, Never>?
    private let converter = BufferConverter()

    // SFSpeechRecognizer path
    private var legacyRecognizer: SFSpeechRecognizer?
    private var legacyRequest: SFSpeechAudioBufferRecognitionRequest?
    private var legacyTask: SFSpeechRecognitionTask?

    // Session recording, written from the mic tap. Timestamps in TimedWord are
    // relative to the start of this file, which is what makes A/B slicing work.
    private var recordingFile: AVAudioFile?
    private(set) var recordingURL: URL?

    /// Ask for permissions and pick the best available backend.
    func prepare() async throws {
        guard await AVAudioApplication.requestRecordPermission() else {
            throw SpeechEngineError.microphoneDenied
        }

        let isEnglish: (Locale) -> Bool = { $0.identifier(.bcp47).lowercased().hasPrefix("en") }
        let supported = await SpeechTranscriber.supportedLocales
        let installed = await SpeechTranscriber.installedLocales

        if supported.contains(where: isEnglish) || installed.contains(where: isEnglish) {
            let transcriber = SpeechTranscriber(
                locale: locale,
                transcriptionOptions: [],
                reportingOptions: [.volatileResults],
                attributeOptions: [.audioTimeRange])
            self.transcriber = transcriber

            // Downloads the on-device speech model if it isn't installed yet.
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
            analyzer = SpeechAnalyzer(modules: [transcriber])
            analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
            backend = .analyzer
            return
        }

        // Fallback: SFSpeechRecognizer (needs its own authorization).
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard status == .authorized else { throw SpeechEngineError.speechDenied }
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw SpeechEngineError.localeUnsupported
        }
        legacyRecognizer = recognizer
        backend = .legacy
    }

    func start(onUpdate: @escaping @MainActor (Update) -> Void) async throws {
        guard let backend else { throw SpeechEngineError.notPrepared }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        startRecordingFile()

        switch backend {
        case .analyzer:
            try await startAnalyzer(onUpdate: onUpdate)
        case .legacy:
            try startLegacy(onUpdate: onUpdate)
        }
        audioEngine.prepare()
        try audioEngine.start()
    }

    func stop() async {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recordingFile = nil  // releasing flushes the file

        inputBuilder?.finish()
        inputBuilder = nil
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        recognizerTask?.cancel()
        recognizerTask = nil

        legacyRequest?.endAudio()
        legacyTask?.finish()
        legacyRequest = nil
        legacyTask = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Session recording

    private func startRecordingFile() {
        recordingFile = nil
        recordingURL = nil
        do {
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Recordings", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent("read-\(Int(Date().timeIntervalSince1970)).caf")
            let tapFormat = audioEngine.inputNode.outputFormat(forBus: 0)
            recordingFile = try AVAudioFile(forWriting: url, settings: tapFormat.settings)
            recordingURL = url
        } catch {
            print("ACCENT recording unavailable: \(error)")  // session still works, just no A/B audio
        }
    }

    // MARK: - SpeechAnalyzer backend

    private func startAnalyzer(onUpdate: @escaping @MainActor (Update) -> Void) async throws {
        guard let analyzer, let transcriber else { throw SpeechEngineError.notPrepared }

        recognizerTask = Task {
            do {
                for try await result in transcriber.results {
                    let words = Self.timedWords(from: result.text)
                    let isFinal = result.isFinal
                    await MainActor.run {
                        onUpdate(Update(words: words, isFinal: isFinal))
                    }
                }
            } catch {
                // Cancellation or analyzer teardown — nothing to surface.
            }
        }

        let (inputSequence, builder) = AsyncStream<AnalyzerInput>.makeStream()
        inputBuilder = builder

        let inputNode = audioEngine.inputNode
        let tapFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { [weak self] buffer, _ in
            guard let self else { return }
            try? self.recordingFile?.write(from: buffer)
            guard let format = self.analyzerFormat else { return }
            guard let converted = try? self.converter.convert(buffer, to: format) else { return }
            self.inputBuilder?.yield(AnalyzerInput(buffer: converted))
        }
        try await analyzer.start(inputSequence: inputSequence)
    }

    /// Flattens an analyzer transcript into words. Each attributed run carries
    /// an `audioTimeRange`; a run spanning several words gets its range
    /// apportioned across them by expand().
    private static func timedWords(from transcript: AttributedString) -> [TimedWord] {
        var words: [TimedWord] = []
        for run in transcript.runs {
            let range = run.audioTimeRange
            words += TimedWord.expand(
                text: String(transcript[run.range].characters),
                confidence: nil,
                start: range.map { $0.start.seconds },
                duration: range.map { $0.duration.seconds })
        }
        return words
    }

    // MARK: - SFSpeechRecognizer backend

    private func startLegacy(onUpdate: @escaping @MainActor (Update) -> Void) throws {
        guard let recognizer = legacyRecognizer else { throw SpeechEngineError.notPrepared }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        legacyRequest = request

        legacyTask = recognizer.recognitionTask(with: request) { result, error in
            if let error { print("ACCENT sfspeech error: \(error)") }
            guard let result else { return }
            if result.isFinal {
                print("ACCENT final segments: \(result.bestTranscription.segments.map { "\($0.substring)|c\($0.confidence)|t\($0.timestamp)+\($0.duration)" })")
            }
            // Partial results report confidence 0 and no timing — map those to
            // nil. A hypothesis reset arrives as a final whose transcription is
            // one empty segment; expand() drops empty tokens, so downstream
            // code detects the reset as an empty word list. On-device
            // recognition can return multi-word segments — expand() splits
            // them and apportions the segment's time range.
            let words = result.bestTranscription.segments.flatMap { segment in
                TimedWord.expand(
                    text: segment.substring,
                    confidence: segment.confidence > 0 ? Double(segment.confidence) : nil,
                    start: segment.duration > 0 ? segment.timestamp : nil,
                    duration: segment.duration > 0 ? segment.duration : nil)
            }
            let isFinal = result.isFinal
            Task { @MainActor in
                onUpdate(Update(words: words, isFinal: isFinal))
            }
        }

        let inputNode = audioEngine.inputNode
        let tapFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { [weak self] buffer, _ in
            guard let self else { return }
            try? self.recordingFile?.write(from: buffer)
            self.legacyRequest?.append(buffer)
        }
    }
}

/// Converts microphone buffers to the analyzer's preferred format.
final class BufferConverter {
    enum ConversionError: Error { case failed }

    private var converter: AVAudioConverter?

    func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        if buffer.format == format { return buffer }

        if converter == nil || converter?.outputFormat != format || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: format)
            converter?.primeMethod = .none
        }
        guard let converter else { throw ConversionError.failed }

        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw ConversionError.failed
        }

        var consumed = false
        var conversionError: NSError?
        converter.convert(to: output, error: &conversionError) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        if let conversionError { throw conversionError }
        return output
    }
}
