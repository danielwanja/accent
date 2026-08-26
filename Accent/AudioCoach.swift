import AVFoundation
import os

/// One audio-session configuration for the app's whole life: .playAndRecord,
/// spoken-audio mode, speaker output. Flipping categories between recording
/// and playback left dead output units behind on device — TTS "played"
/// zero-byte buffers ("AudioQueue underflow: injecting silence"). Configure
/// once, never deactivate.
enum AudioSessionController {
    private static let configured = OSAllocatedUnfairLock(initialState: false)

    static func ensureConfigured() {
        configured.withLock { done in
            guard !done else { return }
            do {
                let session = AVAudioSession.sharedInstance()
                // Default mode: .spokenAudio constrained the capture chain
                // (recordings sounded duller than a voice memo).
                try session.setCategory(
                    .playAndRecord,
                    options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP])
                try? session.setPreferredSampleRate(48000)
                done = true
            } catch {
                print("ACCENT audio: session configure failed: \(error)")
            }
        }
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
    private var player: AVAudioPlayer?
    private var stopItem: DispatchWorkItem?

    // Best available en-US voice; premium/enhanced when the user has one downloaded.
    private static let voice: AVSpeechSynthesisVoice? =
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == "en-US" }
            .max { $0.quality.rawValue < $1.quality.rawValue }

    func speakReference(_ text: String, slow: Bool = false) {
        stopAll()
        activatePlayback()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.voice
        utterance.rate = slow ? 0.35 : AVSpeechUtteranceDefaultSpeechRate
        print("ACCENT audio: speak \"\(text)\" voice=\(Self.voice?.name ?? "default")")
        let synthesizer = AVSpeechSynthesizer()
        synthesizer.delegate = self
        self.synthesizer = synthesizer
        synthesizer.speak(utterance)
    }

    func playSlice(recording url: URL, start: TimeInterval, duration: TimeInterval) {
        stopAll()
        activatePlayback()
        do {
            let slice = try Self.extractSlice(from: url, start: start, duration: duration)
            let player = try AVAudioPlayer(contentsOf: slice)
            self.player = player
            player.delegate = self
            player.volume = 1
            guard player.prepareToPlay() else {
                print("ACCENT audio: prepareToPlay failed for \(slice.lastPathComponent)")
                return
            }
            let began = player.play()
            print("ACCENT audio: slice t=\(String(format: "%.2f", start))s dur=\(String(format: "%.2f", duration))s began=\(began)")
        } catch {
            print("ACCENT audio: slice player failed: \(error)")
        }
    }

    /// Cut the word's slice into a temp file, peak-normalized: raw mic level
    /// is far below synthesized speech, and quiet reads as muffled next to
    /// the NATIVE reference.
    private static func extractSlice(from url: URL, start: TimeInterval, duration: TimeInterval) throws -> URL {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let pad = 0.08
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

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("word-slice.caf")
        try? FileManager.default.removeItem(at: tmp)
        // Inner scope so the AVAudioFile flushes before the player opens it.
        do {
            let out = try AVAudioFile(forWriting: tmp, settings: format.settings)
            try out.write(from: buffer)
        }
        return tmp
    }

    func stopAll() {
        synthesizer?.stopSpeaking(at: .immediate)
        synthesizer = nil
        player?.stop()
        player = nil
        stopItem?.cancel()
        stopItem = nil
    }

    /// The app runs one session configuration for its whole life (see
    /// AudioSessionController) — category flips between record and playback
    /// are what produced dead output units. Just make sure it's active and
    /// on the speaker.
    private func activatePlayback() {
        let session = AVAudioSession.sharedInstance()
        AudioSessionController.ensureConfigured()
        do {
            try session.setActive(true)
        } catch {
            print("ACCENT audio: setActive failed: \(error)")
        }
        if session.category == .playAndRecord {
            do { try session.overrideOutputAudioPort(.speaker) } catch {
                print("ACCENT audio: speaker override failed: \(error)")
            }
        }
        print("ACCENT audio: session category=\(session.category.rawValue) route=\(session.currentRoute.outputs.map(\.portType.rawValue).joined(separator: ","))")
    }

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
