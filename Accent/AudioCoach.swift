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
                try AVAudioSession.sharedInstance().setCategory(
                    .playAndRecord, mode: .spokenAudio,
                    options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP])
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
            let player = try AVAudioPlayer(contentsOf: url)
            self.player = player
            player.delegate = self
            player.volume = 1
            guard player.prepareToPlay() else {
                print("ACCENT audio: prepareToPlay failed for \(url.lastPathComponent)")
                return
            }
            // A hair of context on each side keeps clipped consonants audible;
            // clamp so a drifted timestamp can't seek past the file.
            let pad = 0.08
            let from = min(max(0, start - pad), max(0, player.duration - 0.1))
            player.currentTime = from
            let began = player.play()
            print("ACCENT audio: slice \(url.lastPathComponent) t=\(String(format: "%.2f", from))s dur=\(String(format: "%.2f", duration))s began=\(began)")
            let item = DispatchWorkItem { [weak self] in self?.player?.stop() }
            stopItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 2 * pad, execute: item)
        } catch {
            print("ACCENT audio: slice player failed: \(error)")
        }
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
