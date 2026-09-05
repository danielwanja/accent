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
        .modelContainer(for: TakeRecord.self, inMemory: isTestLaunch)
    }

    private var isTestLaunch: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-audioSmokeTest")
            || ProcessInfo.processInfo.arguments.contains("-testWordDetails")
        #else
        return false
        #endif
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
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-audioSmokeTest") {
                Task { await AudioCoach.runPlaybackSmokeTest() }
                return
            }
            if ProcessInfo.processInfo.arguments.contains("-testWordDetails") {
                app.tab = .read
                return
            }
            #endif
            Lexicon.warmUp()
            PhonemeScorer.beginLoading()  // logs readiness when done; nothing blocks on it
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
        if let index = args.firstIndex(of: "-autoread"), index + 1 < args.count {
            // "-autoread 6" = one 6s take; "-autoread 6x2" = two back-to-back.
            let spec = args[index + 1].split(separator: "x")
            if let seconds = Double(spec[0]) {
                let repeats = spec.count > 1 ? (Int(spec[1]) ?? 1) : 1
                app.tab = .read
                Task { @MainActor in
                    for round in 0..<repeats {
                        await app.session.start()
                        try? await Task.sleep(for: .seconds(seconds))
                        await app.session.stop()
                        if round < repeats - 1 { try? await Task.sleep(for: .seconds(3)) }
                    }
                }
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
        if args.contains("-audiotest") {
            // Exercises both playback paths with console diagnostics.
            Task { @MainActor in
                let coach = AudioCoach()
                coach.speakReference("think")
                try? await Task.sleep(for: .seconds(2.5))
                let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("Recordings", isDirectory: true)
                if let newest = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).first {
                    coach.playSlice(recording: newest, start: 1.0, duration: 1.2)
                    try? await Task.sleep(for: .seconds(2))
                }
            }
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
