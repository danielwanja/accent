import SwiftUI

struct ReadingView: View {
    @State private var session = ReadingSession()
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Spacer()
            Text(passageText)
                .font(.system(size: 32, weight: .regular, design: .serif))
                .lineSpacing(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)
                .animation(.easeOut(duration: 0.18), value: session.states)
            Spacer()
            statusLine
            controls
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paper)
    }

    private var header: some View {
        HStack {
            Text("ACCENT")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .kerning(3)
                .foregroundStyle(Theme.muted)
            Spacer()
            Text("M0 · PASSAGE 1")
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .kerning(1.5)
                .foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
    }

    private var passageText: AttributedString {
        var result = AttributedString()
        for (index, word) in session.passage.words.enumerated() {
            var piece = AttributedString(word.display)
            switch session.states[index] {
            case .upcoming:
                piece.foregroundColor = Theme.upcoming
            case .current:
                piece.foregroundColor = Theme.ink
                piece.backgroundColor = Theme.amberWash
            case .spoken:
                piece.foregroundColor = Theme.ink
            case .missed:
                piece.foregroundColor = Theme.ink
                piece.underlineStyle = Text.LineStyle(pattern: .solid, color: Theme.accent)
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
        case .idle: return "TAP RECORD, THEN READ THE SENTENCE ALOUD"
        case .preparing: return "PREPARING SPEECH MODEL…"
        case .listening: return "LISTENING"
        case .finished: return "DONE — RED UNDERLINE MARKS A MISS"
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
            .disabled(session.status == .preparing)

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
}
