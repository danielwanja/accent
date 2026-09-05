import SwiftUI
import SwiftData

struct ReadingView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @State private var pulse = false
    @State private var showingPicker = false
    @State private var selectedWord: SelectedWord?

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
                            withAnimation(.spring(duration: 0.3)) {
                                selectedWord = SelectedWord(id: index)
                            }
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
        .onAppear {
            #if DEBUG
            // "-showword N" opens word N's card once the take finishes.
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-testWordDetails") {
                selectedWord = SelectedWord(id: 0)
            }
            if let index = args.firstIndex(of: "-showword"), index + 1 < args.count,
               let wordIndex = Int(args[index + 1]) {
                Task { @MainActor in
                    while session.status != .finished { try? await Task.sleep(for: .seconds(1)) }
                    if session.results.indices.contains(wordIndex) {
                        withAnimation { selectedWord = SelectedWord(id: wordIndex) }
                    }
                }
            }
            #endif
        }
        .onChange(of: session.status) { _, status in
            if status == .finished { saveTake() }
            // A new take invalidates the open word card.
            if status == .preparing || status == .listening {
                withAnimation { selectedWord = nil }
            }
        }
        .task(id: currentWord) {
            guard session.isRecording, currentWord != nil else { return }
            // Coalesce bursty transcript updates outside SwiftUI's render pass.
            // sensoryFeedback also uses onChange internally and emitted a
            // multiple-updates-per-frame warning for this stream.
            do { try await Task.sleep(for: .milliseconds(60)) }
            catch { return }
            guard !Task.isCancelled, session.isRecording else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6)
        }
        .sheet(isPresented: $showingPicker) {
            PassagePickerView { title, text in
                session.load(title: title, text: text)
            }
        }
        .sheet(item: $selectedWord) { selected in
            if session.results.indices.contains(selected.id) {
                NavigationStack {
                    WordDetailView(
                        word: session.passage.words[selected.id],
                        result: session.results[selected.id],
                        recordingURL: session.recordingURL)
                        .id(selected.id)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button {
                                    selectedWord = nil
                                } label: {
                                    Image(systemName: "xmark")
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .accessibilityLabel("Close word details")
                                .accessibilityIdentifier("closeWordDetails")
                            }
                        }
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Theme.paper)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            }
        }
    }

    private var currentWord: Int? {
        session.results.firstIndex { $0.state == .current }
    }

    /// Persist a finished take — only the words that were actually read.
    private func saveTake() {
        let stored: [StoredWord] = zip(session.passage.words, session.results).compactMap { word, result in
            let state: String
            switch result.state {
            case .spoken: state = "spoken"
            case .accented: state = "accented"
            case .missed: state = "missed"
            case .uncertain: state = "uncertain"
            case .upcoming, .current: return nil
            }
            return StoredWord(
                display: word.display, norm: word.norm, state: state,
                heard: result.heard, confidence: result.confidence,
                phonemes: result.phonemeScores?.map { StoredPhoneme(arpa: $0.arpa, gop: $0.gop, needsPractice: $0.needsPractice, assessed: $0.isAssessed) },
                stressOK: result.stressCheck?.ok)
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
            .disabled(session.isBusy)
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
            case .uncertain:
                piece.foregroundColor = Theme.ink
                if tappable { piece.underlineStyle = Text.LineStyle(pattern: .dot, color: Theme.muted) }
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
        case .listening: return "LISTENING — FOLLOW THE HIGHLIGHT"
        case .scoring: return "SCORING PHONEMES…"
        case .finished:
            return session.scoringAvailable
                ? "AMBER: PRACTICE · DOTTED: CHECK AUDIO\nTAP A WORD FOR GUIDANCE"
                : "WORDS CHECKED · SOUND ASSESSMENT UNAVAILABLE\nTAP A WORD TO LISTEN AND PRACTICE"
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
            .disabled(session.isBusy)
        }
        .padding(.bottom, 40)
    }
}

#Preview {
    ReadingView()
        .environment(AppModel())
        .modelContainer(for: TakeRecord.self, inMemory: true)
}
