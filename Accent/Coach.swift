import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Generates practice content for a target issue. Uses the on-device Apple
/// Intelligence model when available (real devices); falls back to the curated
/// drill in the taxonomy elsewhere (simulator, older hardware, model busy).
enum Coach {
    struct Drill {
        let title: String
        let text: String
        let generated: Bool   // true when the LLM wrote it
    }

    static func drill(for issue: Issue) async -> Drill {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability {
                do {
                    let session = LanguageModelSession(instructions: """
                        You write short practice passages for a French speaker polishing \
                        American English pronunciation. Passages must be natural prose, \
                        2 to 3 sentences, 25 to 40 words total, and densely packed with \
                        words containing the target sound. No proper nouns, no rare words.
                        """)
                    let prompt = """
                        Target sound: \(issue.name) \(issue.phonemes). \
                        Typical error: \(issue.why) \
                        Write one practice passage saturated with this sound.
                        """
                    let response = try await session.respond(
                        to: prompt, generating: GeneratedDrill.self)
                    let text = response.content.passage
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    // Guard against off-target generations: the passage must
                    // actually exercise the issue several times.
                    let hits = text.split(whereSeparator: \.isWhitespace)
                        .map { Passage.normalize(String($0)) }
                        .filter { Phonics.issueIDs(for: $0).contains(issue.id) }
                        .count
                    if hits >= 4 {
                        return Drill(title: "\(issue.name) Practice", text: text, generated: true)
                    }
                } catch {
                    print("ACCENT coach generation failed: \(error)")
                }
            }
        }
        #endif
        return Drill(title: issue.drillTitle, text: issue.drillText, generated: false)
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct GeneratedDrill {
    @Guide(description: "A 2-3 sentence practice passage saturated with the target sound")
    var passage: String
}
#endif
