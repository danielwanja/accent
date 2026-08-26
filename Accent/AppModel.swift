import Foundation
import Observation

/// Shared app state: the selected tab and the one reading session, so the
/// Today screen can load a drill or diagnostic and jump to the Read tab.
@MainActor
@Observable
final class AppModel {
    enum Tab: Hashable {
        case today, read, progress
    }

    var tab: Tab = .today
    let session = ReadingSession()
    var isGeneratingDrill = false

    /// The onboarding passage: one read that touches every issue in the map.
    static let diagnostic = LibraryPassage(
        id: "diagnostic",
        title: "Diagnostic",
        focus: "All ten issues in one read",
        text: "This Thursday three brothers heard that the harbor hotel had a heated pool. "
            + "Please sit in this seat and feel the deep heat. "
            + "They walked, asked questions, and watched the ships arrive. "
            + "Development of a rich vocabulary is necessary, whether you catch each chance or not.")

    func startReading(title: String, text: String) {
        session.load(title: title, text: text)
        tab = .read
    }

    func startDiagnostic() {
        startReading(title: Self.diagnostic.title, text: Self.diagnostic.text)
    }

    func startPractice(for issue: Issue) {
        guard !isGeneratingDrill else { return }
        isGeneratingDrill = true
        Task {
            let drill = await Coach.drill(for: issue)
            isGeneratingDrill = false
            startReading(title: drill.title, text: drill.text)
        }
    }
}
