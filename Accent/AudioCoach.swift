import AVFoundation
import os

/// Serialize blocking audio setup, file I/O, and player operations away from UI.
private enum AudioWork {
    static let queue = DispatchQueue(label: "com.n-so.accent.audio", qos: .userInitiated)

    static func perform<T>(_ operation: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                dispatchPrecondition(condition: .notOnQueue(.main))
                do { continuation.resume(returning: try operation()) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }
}

/// One shared configuration for recording and playback. Activation requests
/// share their in-flight work; an interruption can be recovered on the next request.
actor AudioSessionController {
    static let shared = AudioSessionController()
    private var configured = false
    private var activation: Task<Void, Error>?

    func activate() async throws {
        if let activation { return try await activation.value }
        let needsConfiguration = !configured
        let task = Task {
            if needsConfiguration {
                try await AudioWork.perform {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.playAndRecord,
                                            options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP])
                    try? session.setPreferredSampleRate(48000)
                }
            }
            if #available(iOS 27.0, *) {
                guard try await AVAudioSession.sharedInstance().activate(options: []) else {
                    throw NSError(domain: "AudioSessionController", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "Audio activation did not complete."])
                }
            } else {
                try await AudioWork.perform {
                    try AVAudioSession.sharedInstance().setActive(true)
                }
            }
        }
        activation = task
        defer { activation = nil }
        try await task.value
        configured = true
    }
}

/// Cancellation is visible to queued file/player work immediately, even while
/// the main actor is waiting for session activation or clip preparation.
private final class PlaybackRequest: Sendable {
    private let cancelled = OSAllocatedUnfairLock(initialState: false)
    func cancel() { cancelled.withLock { $0 = true } }
    func checkCancellation() throws {
        if cancelled.withLock({ $0 }) { throw CancellationError() }
    }
}

/// The player and its temporary file are accessed only on AudioWork.queue.
private final class ClipPlayback: @unchecked Sendable {
    private var player: AVAudioPlayer?
    private var file: URL?

    func play(recording: URL, start: TimeInterval, duration: TimeInterval, pad: TimeInterval,
              request: PlaybackRequest, delegate: AVAudioPlayerDelegate) async throws {
        try await AudioWork.perform { [self] in
            try request.checkCancellation()
            stopOnQueue()
            let slice = try AudioCoach.extractSlice(from: recording, start: start, duration: duration, pad: pad)
            do {
                try request.checkCancellation()
                let prepared = try AVAudioPlayer(contentsOf: slice)
                prepared.delegate = delegate
                prepared.volume = 1
                guard prepared.prepareToPlay() else {
                    throw NSError(domain: "AudioCoach", code: 2)
                }
                try request.checkCancellation()
                guard prepared.play() else { throw NSError(domain: "AudioCoach", code: 3) }
                player = prepared
                file = slice
                print("ACCENT audio: slice t=\(String(format: "%.2f", start))s dur=\(String(format: "%.2f", duration))s began=true")
            } catch {
                try? FileManager.default.removeItem(at: slice)
                throw error
            }
        }
    }

    func stop() {
        AudioWork.queue.async { [self] in stopOnQueue() }
    }

    private func stopOnQueue() {
        dispatchPrecondition(condition: .onQueue(AudioWork.queue))
        player?.stop()
        player = nil
        if let file { try? FileManager.default.removeItem(at: file) }
        file = nil
    }
}

/// Plays reference pronunciations (synthesized native voice) and slices of the
/// user's own session recording — the two halves of the word A/B.
@MainActor
final class AudioCoach: NSObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    // Recreated per utterance: a synthesizer that outlives audio-session
    // changes can end up bound to a dead output unit and render zero-byte
    // buffers ("AudioQueue underflow: injecting silence") — speech that
    // "plays" silently.
    private var synthesizer: AVSpeechSynthesizer?
    private let clips = ClipPlayback()
    private var playbackTask: Task<Void, Never>?
    private var request: PlaybackRequest?

    // Voice discovery can synchronously wait on system services. Resolve it
    // off the main actor as well, and share the lookup across playback requests.
    private static let voiceTask: Task<AVSpeechSynthesisVoice?, Never> = Task.detached(priority: .userInitiated) {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == "en-US" }
            .max { $0.quality.rawValue < $1.quality.rawValue }
    }

    func speakReference(_ text: String, slow: Bool = false) {
        stopAll()
        let request = PlaybackRequest()
        self.request = request
        playbackTask = Task { [weak self] in
            do {
                try await AudioSessionController.shared.activate()
                try request.checkCancellation()
                let voice = await Self.voiceTask.value
                try request.checkCancellation()
                guard let self else { return }
                let utterance = AVSpeechUtterance(string: text)
                utterance.voice = voice
                utterance.rate = slow ? 0.35 : AVSpeechUtteranceDefaultSpeechRate
                let synthesizer = AVSpeechSynthesizer()
                synthesizer.usesApplicationAudioSession = true
                synthesizer.delegate = self
                self.synthesizer = synthesizer
                print("ACCENT audio: speak \"\(text)\" voice=\(voice?.name ?? "default")")
                synthesizer.speak(utterance)
            } catch is CancellationError {
                // Another tap or dismissal replaced this request.
            } catch {
                print("ACCENT audio: reference failed: \(error)")
            }
        }
    }

    func playSlice(recording url: URL, start: TimeInterval, duration: TimeInterval, pad: TimeInterval = 0.08) {
        stopAll()
        let request = PlaybackRequest()
        self.request = request
        playbackTask = Task { [weak self] in
            do {
                try await AudioSessionController.shared.activate()
                try request.checkCancellation()
                guard let self else { return }
                try await clips.play(recording: url, start: start, duration: duration, pad: pad,
                                     request: request, delegate: self)
            } catch is CancellationError {
                // Another tap or dismissal replaced this request.
            } catch {
                print("ACCENT audio: slice player failed: \(error)")
            }
        }
    }

    /// Cut the word's slice into a temp file, peak-normalized: raw mic level
    /// is far below synthesized speech, and quiet reads as muffled next to
    /// the NATIVE reference.
    nonisolated fileprivate static func extractSlice(from url: URL, start: TimeInterval, duration: TimeInterval, pad: TimeInterval) throws -> URL {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let startFrame = AVAudioFramePosition(max(0, start - pad) * format.sampleRate)
        let frameCount = AVAudioFrameCount(max(0, min(
            Double(file.length - startFrame),
            (duration + 2 * pad) * format.sampleRate)))
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(domain: "AudioCoach", code: 1)
        }
        file.framePosition = startFrame
        try file.read(into: buffer, frameCount: frameCount)

        if let channels = buffer.floatChannelData {
            var peak: Float = 0
            for channel in 0..<Int(format.channelCount) {
                for i in 0..<Int(buffer.frameLength) {
                    peak = max(peak, abs(channels[channel][i]))
                }
            }
            if peak > 0.001, peak < 0.85 {
                let gain = 0.9 / peak
                for channel in 0..<Int(format.channelCount) {
                    for i in 0..<Int(buffer.frameLength) {
                        channels[channel][i] *= gain
                    }
                }
                print("ACCENT audio: slice normalized, peak \(String(format: "%.3f", peak)) gain ×\(String(format: "%.1f", gain))")
            }
        }

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("word-slice-\(UUID().uuidString).caf")
        try? FileManager.default.removeItem(at: tmp)
        // Inner scope so the AVAudioFile flushes before the player opens it.
        do {
            let out = try AVAudioFile(forWriting: tmp, settings: format.settings)
            try out.write(from: buffer)
        }
        return tmp
    }

    func stopAll() {
        request?.cancel()
        request = nil
        playbackTask?.cancel()
        playbackTask = nil
        synthesizer?.stopSpeaking(at: .immediate)
        synthesizer = nil
        clips.stop()
    }

    #if DEBUG
    /// Exercises real activation/player APIs with a synthetic silent file,
    /// without a microphone or a user's saved recording.
    static func runPlaybackSmokeTest() async {
        setbuf(stdout, nil)
        print("ACCENT audio smoke: starting")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("audio-smoke-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            try await AudioWork.perform {
                let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
                let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8000)!
                buffer.frameLength = 8000
                buffer.floatChannelData![0].initialize(repeating: 0, count: 8000)
                let file = try AVAudioFile(forWriting: url, settings: format.settings)
                try file.write(from: buffer)
            }
            let coach = AudioCoach()
            defer { coach.stopAll() }
            // Cancel before the asynchronous setup has a chance to complete.
            coach.speakReference("Cancelled reference must not play")
            let cancelledReference = coach.playbackTask
            coach.stopAll()
            await cancelledReference?.value
            coach.playSlice(recording: url, start: 0, duration: 0.3)
            let cancelledClip = coach.playbackTask
            coach.stopAll()
            await cancelledClip?.value
            print("ACCENT audio smoke: cancelled requests drained")
            for _ in 0..<2 {
                coach.speakReference("think")
                await coach.playbackTask?.value
                try await Task.sleep(for: .seconds(1.5))
                coach.playSlice(recording: url, start: 0, duration: 0.3)
                await coach.playbackTask?.value
                try await Task.sleep(for: .milliseconds(700))
            }
            print("ACCENT audio smoke: completed")
        } catch {
            print("ACCENT audio smoke: failed \(error)")
        }
    }
    #endif

    // MARK: - Delegates (diagnostics)

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        print("ACCENT audio: speech started")
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        print("ACCENT audio: speech finished")
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        print("ACCENT audio: speech cancelled")
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        print("ACCENT audio: slice finished ok=\(flag)")
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        print("ACCENT audio: slice decode error: \(String(describing: error))")
    }
}
