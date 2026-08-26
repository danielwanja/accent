import AVFoundation

/// Plays reference pronunciations (synthesized native voice) and slices of the
/// user's own session recording — the two halves of the word A/B.
@MainActor
final class AudioCoach {
    private let synthesizer = AVSpeechSynthesizer()
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
        synthesizer.speak(utterance)
    }

    func playSlice(recording url: URL, start: TimeInterval, duration: TimeInterval) {
        stopAll()
        activatePlayback()
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
        self.player = player
        // A hair of context on each side keeps clipped consonants audible.
        let pad = 0.08
        player.currentTime = max(0, start - pad)
        player.play()
        let item = DispatchWorkItem { [weak self] in self?.player?.stop() }
        stopItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 2 * pad, execute: item)
    }

    func stopAll() {
        synthesizer.stopSpeaking(at: .immediate)
        player?.stop()
        player = nil
        stopItem?.cancel()
        stopItem = nil
    }

    private func activatePlayback() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
    }
}
