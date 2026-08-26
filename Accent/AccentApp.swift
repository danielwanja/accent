import SwiftUI
import SwiftData

@main
struct AccentApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
        }
        .modelContainer(for: TakeRecord.self)
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context

    var body: some View {
        @Bindable var app = app
        TabView(selection: $app.tab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max") }
                .tag(AppModel.Tab.today)
            ReadingView()
                .tabItem { Label("Read", systemImage: "text.book.closed") }
                .tag(AppModel.Tab.read)
            ProgressScreen()
                .tabItem { Label("Progress", systemImage: "chart.bar") }
                .tag(AppModel.Tab.progress)
        }
        .tint(Theme.accent)
        .onAppear {
            Lexicon.warmUp()
            #if DEBUG
            Task.detached(priority: .utility) {
                print("ACCENT phoneme scorer ready: \(PhonemeScorer.shared != nil)")
            }
            #endif
            handleLaunchArguments()
        }
    }

    /// DEBUG-only hooks so screens can be exercised from the command line:
    /// -seedDemo inserts sample takes, -tab today|read|progress picks the tab.
    private func handleLaunchArguments() {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-wipe") {
            try? context.delete(model: TakeRecord.self)
            try? context.save()
            let recordings = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Recordings", isDirectory: true)
            try? FileManager.default.removeItem(at: recordings)
        }
        if args.contains("-seedDemo") {
            seedDemoTakes()
        }
        if let index = args.firstIndex(of: "-autoread"), index + 1 < args.count,
           let seconds = Double(args[index + 1]) {
            app.tab = .read
            Task { @MainActor in
                await app.session.start()
                try? await Task.sleep(for: .seconds(seconds))
                await app.session.stop()
            }
        }
        if let index = args.firstIndex(of: "-tab"), index + 1 < args.count {
            switch args[index + 1] {
            case "read": app.tab = .read
            case "progress": app.tab = .progress
            default: app.tab = .today
            }
        }
        if let index = args.firstIndex(of: "-practice"), index + 1 < args.count,
           let issue = Phonics.issue(args[index + 1]) {
            app.startPractice(for: issue)
        }
        #endif
    }

    #if DEBUG
    private func seedDemoTakes() {
        let existing = (try? context.fetchCount(FetchDescriptor<TakeRecord>())) ?? 0
        guard existing == 0 else { return }
        let demos: [(String, String, TimeInterval, [(String, String)])] = [
            ("Diagnostic", AppModel.diagnostic.text, -3 * 86400, [
                ("this", "missed"), ("thursday", "missed"), ("three", "missed"), ("brothers", "accented"),
                ("that", "missed"), ("the", "spoken"), ("harbor", "accented"), ("hotel", "spoken"),
                ("heated", "missed"), ("sit", "accented"), ("seat", "spoken"), ("feel", "spoken"),
                ("deep", "spoken"), ("heat", "missed"), ("walked", "spoken"), ("asked", "missed"),
                ("ships", "spoken"), ("development", "accented"), ("whether", "missed"), ("catch", "spoken")]),
            ("TH Drill", Phonics.issue("th")!.drillText, -2 * 86400, [
                ("thirtythree", "missed"), ("thankful", "accented"), ("brothers", "spoken"),
                ("thought", "missed"), ("this", "spoken"), ("thing", "accented"), ("through", "spoken"),
                ("whether", "missed"), ("gather", "spoken"), ("there", "spoken"), ("truth", "accented"),
                ("worth", "spoken"), ("breath", "spoken")]),
            ("TH Drill", Phonics.issue("th")!.drillText, -1 * 86400, [
                ("thirtythree", "accented"), ("thankful", "spoken"), ("brothers", "spoken"),
                ("thought", "spoken"), ("this", "spoken"), ("thing", "spoken"), ("through", "missed"),
                ("whether", "accented"), ("gather", "spoken"), ("there", "spoken"), ("truth", "spoken"),
                ("worth", "spoken"), ("breath", "spoken")]),
        ]
        for (title, text, offset, words) in demos {
            let stored = words.map { word, state in
                StoredWord(display: word, norm: word, state: state, heard: nil, confidence: nil)
            }
            context.insert(TakeRecord(
                date: Date().addingTimeInterval(offset),
                passageTitle: title, passageText: text,
                words: stored, recordingFile: nil))
        }
        try? context.save()
    }
    #endif
}
