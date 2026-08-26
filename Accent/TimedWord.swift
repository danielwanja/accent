import Foundation

/// One recognized word, normalized across speech backends.
struct TimedWord {
    let text: String
    let norm: String
    /// 0…1 word confidence. SFSpeechRecognizer reports it on final results;
    /// SpeechAnalyzer doesn't expose one, so it stays nil there.
    let confidence: Double?
    /// Seconds from the start of the session recording.
    let start: TimeInterval?
    let duration: TimeInterval?
}
