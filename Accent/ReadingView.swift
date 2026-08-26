import SwiftUI
import SwiftData

struct ReadingView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @State private var pulse = false
    @State private var showingPicker = false
    @State private var selectedWord: SelectedWord?
    @State private var lastTickedWord = -1

    private var session: ReadingSession { app.session }

    private struct SelectedWord: Identifiable {
        let id: Int
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Spacer(minLength: 0)
            ScrollView {
                Text(passageText)
                    .font(.system(size: passageFontSize, weight: .regular, design: .serif))
                    .lineSpacing(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                    .animation(.easeOut(duration: 0.18), value: session.results)
                    .accessibilityLabel("Passage: \(session.passage.text)")
                    .environment(\.openURL, OpenURLAction { url in
                        if url.scheme == "accent", let index = Int(url.lastPathComponent),
                           session.results.indices.contains(index) {
                            selectedWord = SelectedWord(id: index)
                        }
                        return .handled
                    })
            }
            .scrollBounceBehavior(.basedOnSize)
            Spacer(minLength: 0)
            statusLine
            controls
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paper)
        .onChange(of: session.status) { _, status in
            if status == .finished { saveTake() }
        }
        .onChange(of: session.results) { _, results in
            // Quiet haptic tick as the highlight advances to a new word.
            guard session.isRecording,
                  let current = results.firstIndex(where: { $0.state == .current }),
                  current != lastTickedWord else { return }
            lastTickedWord = current
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6)
        }
        .sheet(isPresented: $showingPicker) {
            PassagePickerView { title, text in
                session.load(title: title, text: text)
            }
        }
        .sheet(item: $selectedWord) { selected in
            WordDetailView(
                word: session.passage.words[selected.id],
                result: session.results[selected.id],
                recordingURL: session.recordingURL)
                .presentationDetents([.height(340)])
                .presentationDragIndicator(.visible)
        }
    }

    /// Persist a finished take — only the words that were actually read.
    private func saveTake() {
        let stored: [StoredWord] = zip(session.passage.words, session.results).compactMap { word, result in
            let state: String
            switch result.state {
            case .spoken: state = "spoken"
            case .accented: state = "accented"
            case .missed: state = "missed"
            case .upcoming, .current: return nil
            }
            return StoredWord(
                display: word.display, norm: word.norm, state: state,
                heard: result.heard, confidence: result.confidence,
                phonemes: result.phonemeScores?.map { StoredPhoneme(arpa: $0.arpa, gop: $0.gop) })
        }
        guard !stored.isEmpty else { return }
        context.insert(TakeRecord(
            date: Date(),
            passageTitle: session.passageTitle,
            passageText: session.passage.text,
            words: stored,
            recordingFile: session.recordingURL?.lastPathComponent))
        try? context.save()
    }

    private var header: some View {
        HStack {
            Text("ACCENT")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .kerning(3)
                .foregroundStyle(Theme.muted)
            Spacer()
            Button {
                showingPicker = true
            } label: {
                HStack(spacing: 6) {
                    Text(session.passageTitle.uppercased())
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .kerning(1.5)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(Theme.muted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Choose passage")
            .disabled(session.isRecording)
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
    }

    private var passageFontSize: CGFloat {
        session.passage.words.count > 30 ? 26 : 32
    }

    private var passageText: AttributedString {
        let tappable = session.status == .finished
        var result = AttributedString()
        for (index, word) in session.passage.words.enumerated() {
            var piece = AttributedString(word.display)
            switch session.results[index].state {
            case .upcoming:
                piece.foregroundColor = Theme.upcoming
            case .current:
                piece.foregroundColor = Theme.ink
                piece.backgroundColor = Theme.amberWash
            case .spoken:
                piece.foregroundColor = Theme.ink
            case .accented:
                piece.foregroundColor = Theme.ink
                piece.underlineStyle = Text.LineStyle(pattern: .solid, color: Theme.amber)
            case .missed:
                piece.foregroundColor = Theme.ink
                piece.underlineStyle = Text.LineStyle(pattern: .solid, color: Theme.accent)
            }
            if tappable {
                piece.link = URL(string: "accent://word/\(index)")
            }
            result += piece
            if index < session.passage.words.count - 1 {
                result += AttributedString(" ")
            }
        }
        return result
    }

    private var statusLine: some View {
        Text(statusText)
            .font(.system(size: 12, weight: .regular, design: .monospaced))
            .kerning(1)
            .foregroundStyle(statusIsError ? Theme.accent : Theme.muted)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 28)
            .padding(.bottom, 20)
    }

    private var statusText: String {
        switch session.status {
        case .idle: return "TAP RECORD, THEN READ THE PASSAGE ALOUD"
        case .preparing: return "PREPARING SPEECH MODEL…"
        case .listening: return "LISTENING"
        case .scoring: return "SCORING PHONEMES…"
        case .finished: return "DONE — TAP ANY WORD FOR DETAILS"
        case .failed(let message): return message.uppercased()
        }
    }

    private var statusIsError: Bool {
        if case .failed = session.status { return true }
        return false
    }

    private var controls: some View {
        HStack(spacing: 44) {
            // Balances the reset button so the record button stays centered.
            Color.clear.frame(width: 44, height: 44)

            Button(action: session.toggle) {
                ZStack {
                    Circle()
                        .stroke(Theme.line, lineWidth: 2)
                        .frame(width: 76, height: 76)
                    if session.isRecording {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Theme.accent)
                            .frame(width: 30, height: 30)
                            .scaleEffect(pulse ? 0.92 : 1.0)
                            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
                            .onAppear { pulse = true }
                            .onDisappear { pulse = false }
                    } else {
                        Circle()
                            .fill(Theme.accent)
                            .frame(width: 62, height: 62)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(session.isRecording ? "Stop recording" : "Start recording")
            .disabled(session.status == .preparing || session.status == .scoring)

            Button {
                session.reset()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reset")
            .disabled(session.isRecording)
        }
        .padding(.bottom, 40)
    }
}

#Preview {
    ReadingView()
        .environment(AppModel())
        .modelContainer(for: TakeRecord.self, inMemory: true)
}
