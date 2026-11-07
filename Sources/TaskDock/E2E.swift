import AppKit

/// Dev-only end-to-end run (`scripts/e2e.sh`): starts and finishes a real task twice on the first
/// template in `TASKDOCK_DATA_DIR` and writes what it saw to `TASKDOCK_E2E` (JSON), then quits.
/// The template should hold TextEdit, Preview, Helium and Phi; `TASKDOCK_E2E_FILES` = note.txt|image.png.
enum E2E {
    @MainActor
    static func run() {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        // Only ever on scripts/e2e.sh's throwaway folder (data next to the report): the run overwrites
        // the first template's saved state.
        guard let out = env["TASKDOCK_E2E"], let data = env["TASKDOCK_DATA_DIR"],
              URL(fileURLWithPath: data).standardized.path == URL(fileURLWithPath: out).deletingLastPathComponent().appendingPathComponent("data").standardized.path,
              let files = env["TASKDOCK_E2E_FILES"]?.split(separator: "|").map(String.init),
              files.count == 2 else { return }
        let note = URL(fileURLWithPath: files[0]), image = URL(fileURLWithPath: files[1])
        let textEdit = "com.apple.TextEdit", preview = "com.apple.Preview"
        var report: [String: Any] = [:]
        var checks: [String: Bool] = [:]
        func check(_ name: String, _ ok: Bool) { checks[name] = ok; NSLog("TaskDock E2E: \(ok ? "PASS" : "FAIL") \(name)") }
        func off<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T { await Task.detached(operation: work).value }
        func wait(_ seconds: Double, until done: () -> Bool = { false }) async {
            let end = Date().addingTimeInterval(seconds)
            while Date() < end, !done() { try? await Task.sleep(for: .milliseconds(250)) }
        }

        Task { @MainActor in
            let store = Store.shared
            guard let t = store.templates.first else { return }
            await wait(10) { store.browsers > 0 } // the fake browser connects
            check("fake browser connected", store.browsers > 0)
            Snapshot.running(textEdit).forEach { $0.terminate() }
            await wait(5) { !Snapshot.isRunning(textEdit) }
            let previewWasRunning = Snapshot.isRunning(preview)

            // Round 1: start, work, finish.
            store.start(t, goal: "E2E round 1")
            await wait(6)
            check("TextEdit recorded as opened by the task", store.session?.launched?.contains(textEdit) == true)
            check("Preview opened-by-task matches whether it was running", (store.session?.launched?.contains(preview) == true) == !previewWasRunning)
            for (file, app) in [(note, textEdit), (image, preview)] {
                if let a = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app) {
                    let cfg = NSWorkspace.OpenConfiguration(); cfg.activates = false
                    NSWorkspace.shared.open([file], withApplicationAt: a, configuration: cfg, completionHandler: nil)
                }
            }
            var noteWindow: AeroSpace.Window?
            for _ in 0..<16 where noteWindow == nil { // up to about 8 s for TextEdit's window
                noteWindow = await off { AeroSpace.windows().first { $0.app == textEdit && AeroSpace.title(of: $0.id).contains("e2e-note") } }
                if noteWindow == nil { await wait(0.5) }
            }
            await wait(1)
            if let w = noteWindow, let cli = AeroSpace.cli { _ = await off { capture(cli, ["move-node-to-workspace", "--window-id", w.id, "E"]) } }
            check("AeroSpace sees a TextEdit window", noteWindow != nil)
            await wait(8) { store.templates.first?.resume?.tabs.count == 2 } // the fake browser opens two tabs
            report["tabsWhileRunning"] = store.templates.first?.resume?.tabs ?? []
            check("tabs saved while the task runs", store.templates.first?.resume?.tabs.count == 2)

            let previewNow = await off { Snapshot.items([AppRef(bundleID: preview, name: "Preview", path: "/System/Applications/Preview.app")]) }
            report["previewBeforeFinish"] = previewNow.items.map(\.url.path) + previewNow.unread.map { "unread: \($0)" }
            store.finish(note: "e2e note")
            await wait(40) { store.templates.first?.resume?.items.contains { $0.url == note } == true }
            await wait(6) { !Snapshot.isRunning(textEdit) }
            let r = store.templates.first?.resume
            report["savedItems"] = r?.items.map(\.url.path) ?? []
            report["savedWorkspaces"] = r?.workspaces ?? [:]
            check("note.txt saved", r?.items.contains { $0.url == note } == true)
            check("image.png saved", r?.items.contains { $0.url == image } == true)
            check("TextEdit workspace saved as E", r?.workspaces?[textEdit] == "E")
            check("stop note saved", store.templates.first?.lastStopNote == "e2e note")
            check("TextEdit quit on finish", !Snapshot.isRunning(textEdit))
            check("Preview left running if it was open before", !previewWasRunning || Snapshot.isRunning(preview))

            // Round 2: start again; everything should come back.
            await wait(3)
            store.start(store.templates[0], goal: "E2E round 2")
            await wait(12) { false }
            let docs = await off { Snapshot.items([AppRef(bundleID: textEdit, name: "TextEdit", path: "/System/Applications/TextEdit.app")]).items }
            check("note.txt reopened in TextEdit", docs.contains { $0.url == note })
            let ws = await off { AeroSpace.windows().filter { $0.app == textEdit }.map(\.workspace) }
            report["textEditWorkspacesAfter"] = ws
            check("TextEdit window back on workspace E", ws.contains("E"))
            let active = await off { osascript("tell application id \"\(Phi.id)\" to get active space").map { String(decoding: $0, as: UTF8.self) } ?? "" }
            check("Phi on the template's Space", active.contains("\"title\":\"\(t.phiSpace ?? t.name)\""))

            NSLog("TaskDock E2E: round 2 opened by task: \(store.session?.launched ?? [])")
            store.finish(note: "")
            await wait(8) { !Snapshot.isRunning(textEdit) }
            check("TextEdit quit after round 2", !Snapshot.isRunning(textEdit))
            await wait(2)

            report["checks"] = checks
            report["passed"] = checks.values.allSatisfy { $0 }
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: URL(fileURLWithPath: out))
            }
            NSApp.terminate(nil)
        }
        #endif
    }
}
