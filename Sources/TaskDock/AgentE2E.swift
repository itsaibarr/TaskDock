import AppKit
import SQLite3

/// Dev-only end-to-end run of the agent hand-off (`scripts/e2e-agent.sh`). Events go through the real hook
/// binary on a private channel; T3 Code's records come from a test database (`t3.sqlite` in the data folder).
/// Templates in `TASKDOCK_DATA_DIR`: "Coding" and "Writing" (TextEdit), "Further Math" (no apps).
/// Writes what it saw to `TASKDOCK_AGENT_E2E` (JSON), then quits.
enum AgentE2E {
    @MainActor
    static func run() {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        guard let out = env["TASKDOCK_AGENT_E2E"], let data = env["TASKDOCK_DATA_DIR"], env["TASKDOCK_AGENT_CHANNEL"] != nil,
              URL(fileURLWithPath: data).standardized.path == URL(fileURLWithPath: out).deletingLastPathComponent().appendingPathComponent("data").standardized.path
        else { return }
        let textEdit = "com.apple.TextEdit"
        var checks: [String: Bool] = [:]
        func check(_ name: String, _ ok: Bool) { checks[name] = ok; NSLog("TaskDock agent E2E: \(ok ? "PASS" : "FAIL") \(name)") }
        func wait(_ seconds: Double, until done: () -> Bool = { false }) async {
            let end = Date().addingTimeInterval(seconds)
            while Date() < end, !done() { try? await Task.sleep(for: .milliseconds(200)) }
        }
        /// Runs the real hook binary with this JSON on stdin, like Claude Code does.
        func hook(_ json: [String: Any]) {
            let p = Process(), pipe = Pipe()
            p.executableURL = URL(fileURLWithPath: Bundle.main.executablePath!)
            p.arguments = ["agent"]
            p.standardInput = pipe
            try? p.run()
            pipe.fileHandleForWriting.write(try! JSONSerialization.data(withJSONObject: json))
            try? pipe.fileHandleForWriting.close()
            p.waitUntilExit()
        }
        func send(_ event: String, _ session: String, _ extra: [String: Any] = [:]) async {
            hook(["hook_event_name": event, "session_id": session, "cwd": "/tmp/e2e"].merging(extra) { $1 })
            await wait(0.6)
        }
        var pickerOpen: Bool { Windows.picker?.isVisible == true }
        let agents = Agents.shared, store = Store.shared
        /// Banners are "title|where|what happened".
        func finished(_ chat: String) -> Int { Agent.sent.filter { $0.hasPrefix(chat + "|") && $0.contains("|Done ") }.count }
        func needsYou(_ chat: String) -> Bool { Agent.sent.contains { $0.hasPrefix(chat + "|") && $0.hasSuffix("|Waiting for your answer") } }

        Task { @MainActor in
            guard let coding = store.templates.first(where: { $0.name == "Coding" }),
                  let math = store.templates.first(where: { $0.name == "Further Math" }) else { return }
            Snapshot.running(textEdit).forEach { $0.terminate() }
            await wait(5) { !Snapshot.isRunning(textEdit) }
            // The chat's app, as the hook finds it from its parent processes (the app this test runs under).
            let host = Agent.hostApp()
            check("hook finds the chat's app", host != nil)
            Agent.testFrontmost = host // you're in the chat's app when you send a prompt

            // 1. No task running: still tracked and nudged; finishing notifies.
            Agent.testInputAge = 1 // you just pressed ↩
            await send("UserPromptSubmit", "s0", ["session_title": "[Solo.md](Solo.md)"])
            check("hook reaches the app", agents.runs["s0"] != nil)
            check("chat title from T3", agents.runs["s0"]?.title == "Solo.md")
            Agent.testInputAge = 60 // then idle
            await wait(6) { pickerOpen }
            check("nudge without a task", pickerOpen)
            Windows.closePicker()
            await send("Stop", "s0")
            check("finished chat notifies", finished("Solo.md") > 0)
            agents.tick(Date()) // its app is in front and no task runs: you've seen it
            check("finished chat you're looking at clears", agents.runs["s0"]?.seen == true && agents.list.isEmpty)

            // 2. Several chats in one task: one picker for a burst; prompts you didn't send stay silent.
            store.start(coding, goal: "Agent E2E")
            await wait(4) { Snapshot.isRunning(textEdit) }
            Agent.testInputAge = 1
            await send("UserPromptSubmit", "s1", ["session_title": "One"])
            await send("UserPromptSubmit", "s2", ["session_title": "Two"])
            check("chat's app recorded and protected", agents.runs["s1"]?.host == host && agents.hosts.contains(host ?? "-"))
            Agent.testFrontmost = "com.apple.Preview" // you're typing in another app when a sub-thread starts
            await send("UserPromptSubmit", "s3", ["session_title": "Sub"])
            Agent.testFrontmost = host
            Agent.testInputAge = 60
            await wait(6) { pickerOpen }
            check("several chats: picker opens", pickerOpen)
            check("several chats: one picker covers the burst", agents.runs["s1"]?.nudged == true && agents.runs["s2"]?.nudged == true)
            check("prompt you didn't send isn't yours", agents.runs["s3"]?.yours == false)
            Windows.closePicker()
            await wait(4)
            check("no second picker for the same burst", !pickerOpen)

            // 3. A later prompt nudges again, but only once you stop typing.
            Agent.testInputAge = 1
            await send("UserPromptSubmit", "s4", ["session_title": "Four"])
            await wait(5)
            check("nudge waits while you type", !pickerOpen)
            Agent.testInputAge = 60
            await wait(8) { pickerOpen }
            check("each new prompt nudges again", pickerOpen)

            // 4. Pick a task in the nudge: the task is parked, its app keeps running; each chat reports on its own.
            await wait(0.5) // let the picker's view load before driving it
            NotificationCenter.default.post(name: Debug.pickerStep, object: "choose") // first row: the agent's own task is left out
            await wait(1)
            NotificationCenter.default.post(name: Debug.pickerStep, object: "start")
            await wait(4) { store.session?.template.id == math.id }
            check("picking in the nudge switches task", store.session?.template.id == math.id)
            await wait(3) { Snapshot.running(textEdit).first?.isHidden == true } // macOS reports hiding a moment later
            let te = Snapshot.running(textEdit).first
            NSLog("TaskDock agent E2E: TextEdit hidden=\(te?.isHidden ?? false) active=\(te?.isActive ?? false) front=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "-") windows=\(CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID).map { ($0 as! [[String: Any]]).filter { $0[kCGWindowOwnerPID as String] as? Int32 == te?.processIdentifier }.count } ?? -1)")
            check("parked task's app not quit, only hidden", Snapshot.running(textEdit).first?.isHidden == true)
            await send("Stop", "s1")
            check("chat One finished notifies", finished("One") > 0)
            await send("UserPromptSubmit", "s1") // woken up later (background work done, a sub-thread reporting back)
            check("wake-up doesn't nudge", agents.runs["s1"]?.nudged == false && !pickerOpen)
            check("wake-up keeps the chat yours and in its task",
                  agents.runs["s1"]?.yours == true && agents.runs["s1"]?.template == coding.id && agents.runs["s1"]?.state == .working)
            await send("Stop", "s1")
            check("wake-up's finish notifies again", finished("One") == 2)
            await send("PermissionRequest", "s2", ["tool_name": "AskUserQuestion"])
            check("chat Two needs you notifies", needsYou("Two") && agents.runs["s2"]?.state == .needsYou)
            await send("Stop", "s3")
            check("sub-thread finishing stays silent", !Agent.sent.contains { $0.hasPrefix("Sub|") })
            await send("UserPromptSubmit", "s6", ["session_title": "Sub2"]) // a sub-thread you never prompted (input idle)
            await send("PermissionRequest", "s6", ["tool_name": "AskUserQuestion"])
            check("sub-thread that needs you still notifies and shows", needsYou("Sub2") && agents.list.contains { $0.id == "s6" })
            await send("SessionEnd", "s6")
            await send("Stop", "s4", ["background_tasks": [["id": "b1"]]])
            check("turn ending with background work keeps working", agents.runs["s4"]?.state == .working)
            agents.tick(Date().addingTimeInterval(31 * 60))
            check("background work that never ends counts as finished after 30 min",
                  agents.runs["s4"]?.state == .finished && finished("Four") > 0)
            check("menu bar shows every state, needs you first", agents.badge == [.needsYou, .finished])

            // 5. Interrupt: no Stop, only a transcript line.
            let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            func transcript(_ name: String) -> URL { // an empty chat transcript beside the report
                let u = URL(fileURLWithPath: out).deletingLastPathComponent().appendingPathComponent(name)
                try? Data().write(to: u)
                return u
            }
            func append(_ u: URL, _ text: String) { // a transcript line, stamped now
                let h = try? FileHandle(forWritingTo: u); _ = try? h?.seekToEnd()
                try? h?.write(contentsOf: (text.replacingOccurrences(of: "NOW", with: f.string(from: Date())) + "\n").data(using: .utf8)!)
                try? h?.close()
            }
            let t5 = transcript("s5.jsonl")
            Agent.testInputAge = 1
            await send("UserPromptSubmit", "s5", ["transcript_path": t5.path])
            Agent.testInputAge = 60
            append(t5, #"{"type":"user","message":{"content":[{"type":"text","text":"[Request interrupted by user]"}]},"timestamp":"NOW"}"#)
            await wait(3) { agents.runs["s5"]?.state == .finished } // transcripts are read every 2 s
            check("interrupted chat ends quietly but stays yours", agents.runs["s5"]?.state == .finished && agents.runs["s5"]?.yours == true)

            // 5b. A turn that hands work to a T3 delegate ends at once; it's done only after the delegate reports back.
            let t8 = transcript("s8.jsonl")
            Agent.testInputAge = 1
            await send("UserPromptSubmit", "s8", ["session_title": "Council", "transcript_path": t8.path])
            Agent.testInputAge = 60
            for id in ["d1", "d2"] { // council: two delegates in one turn
                append(t8, #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"\#(id)","name":"mcp__t3-code__delegate_task","input":{"task":"review"}}]},"timestamp":"NOW"}"#)
            }
            await send("Stop", "s8")
            check("turn that started delegates keeps working", agents.runs["s8"]?.state == .working && finished("Council") == 0)
            let reportLine = #"{"type":"user","message":{"role":"user","content":"Delegated task node:x (Council) [completed]:\nok"},"timestamp":"NOW"}"#
            await send("UserPromptSubmit", "s8", ["prompt": "Delegated task node: first [completed]"])
            append(t8, reportLine)
            await send("Stop", "s8")
            check("first of two delegates reporting doesn't finish it", agents.runs["s8"]?.state == .working && finished("Council") == 0)
            await send("UserPromptSubmit", "s8", ["prompt": "Delegated task node: second [completed]"])
            append(t8, reportLine)
            await send("Stop", "s8")
            check("last delegate's report finishes it", agents.runs["s8"]?.state == .finished && finished("Council") > 0)
            await send("SessionEnd", "s8")

            // 6. Runs survive a restart.
            let saved = (try? JSONDecoder().decode([String: Agent.Run].self,
                         from: Data(contentsOf: Store.dir.appendingPathComponent("agents.json")))) ?? [:]
            check("runs saved to disk", saved["s2"]?.state == .needsYou && saved["s1"] != nil)

            // 7. Back to the chat's task; finished runs are seen.
            agents.open("s1")
            await wait(4)
            check("open goes back to the chat's task", store.session?.template.id == coding.id)
            check("open keeps the chat's app in front", Snapshot.running(host ?? "-").first?.isHidden == false)
            check("finished runs seen on return", agents.runs["s1"]?.seen == true && agents.runs["s4"]?.seen == true
                  && !agents.list.contains { $0.id == "s1" || $0.id == "s4" })
            check("returning task gets its apps back", store.session?.launched?.contains(textEdit) == true)
            await send("UserPromptSubmit", "s1", ["prompt": "<task-notification>\n<task-id>x</task-id>"]) // a late wake-up
            await send("Stop", "s1")
            check("wake-up after you've seen it still notifies", finished("One") == 3)
            Agent.testInputAge = 1 // you're typing in another chat of the same app when a wake-up arrives
            await send("UserPromptSubmit", "s7", ["prompt": "Delegated task node: x [completed]"])
            Agent.testInputAge = 60
            check("wake-up while you type elsewhere isn't sent by you", agents.runs["s7"]?.yours == false)
            await send("SessionEnd", "s7")

            // 8. Finish while an agent still works: its app stays.
            store.finish(note: "")
            await wait(5)
            check("finish keeps a busy task's app", Snapshot.isRunning(textEdit))
            await send("PostToolUse", "s2", ["tool_name": "AskUserQuestion"])
            check("answering brings it back to working", agents.runs["s2"]?.state == .working)
            await send("SessionEnd", "s2")
            await send("SessionEnd", "s3")
            check("closed chats forgotten", agents.runs["s2"] == nil && agents.runs["s3"] == nil)

            // 9. Once no agent works for it, finishing the task quits its apps as usual.
            store.start(coding, goal: "Agent E2E 2")
            await wait(3)
            store.finish(note: "")
            await wait(8) { !Snapshot.isRunning(textEdit) }
            check("finish quits the app once agents are done", !Snapshot.isRunning(textEdit))

            // 10. Two tasks share an app: it's never quit while the parked one's agent works, even after a restart.
            guard let writing = store.templates.first(where: { $0.name == "Writing" }) else { return }
            store.start(coding, goal: "Shared")
            await wait(4) { Snapshot.isRunning(textEdit) }
            Agent.testInputAge = 1
            await send("UserPromptSubmit", "s11", ["session_title": "Shared"])
            Agent.testInputAge = 60
            store.start(writing, goal: "Write") // Coding is parked; Writing uses TextEdit too
            await wait(3)
            let parkedFile = (try? String(contentsOf: Store.dir.appendingPathComponent("parked.json"), encoding: .utf8)) ?? ""
            check("parked apps saved to disk", parkedFile.contains(textEdit))
            store.finish(note: "")
            await wait(6)
            check("finishing a task keeps an app a parked task shares", Snapshot.isRunning(textEdit))
            await send("SessionEnd", "s11")
            store.start(coding, goal: "Shared 2")
            await wait(3)
            store.finish(note: "")
            await wait(8) { !Snapshot.isRunning(textEdit) }
            check("the shared app is quit once no task needs it", !Snapshot.isRunning(textEdit))

            // 11. Clicking away from the nudge leaves a quiet menu item; Esc leaves nothing.
            store.start(coding, goal: "Focus")
            await wait(4) { Snapshot.isRunning(textEdit) }
            Agent.testInputAge = 1
            await send("UserPromptSubmit", "s12", ["session_title": "Focus"])
            Agent.testInputAge = 60
            await wait(6) { pickerOpen }
            NSLog("TaskDock agent E2E: step 11 picker=\(pickerOpen) run=\(String(describing: agents.runs["s12"].map { ($0.state, $0.yours, $0.nudged, $0.template == coding.id) })) session=\(store.session?.template.name ?? "-") front=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "-")")
            NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: Windows.picker)
            await wait(1)
            NSLog("TaskDock agent E2E: step 11 after resign picker=\(pickerOpen) later=\(String(describing: agents.later)) still=\(String(describing: agents.laterStillWorking))")
            check("clicking away from the nudge leaves a menu item", !pickerOpen && agents.laterStillWorking == coding.id)
            Windows.togglePicker(switching: true, nudge: agents.laterStillWorking) // the menu item
            await wait(1)
            check("the menu item reopens the nudge, once", pickerOpen && agents.later == nil)
            Windows.closePicker() // Esc
            await wait(1)
            check("Esc on the nudge leaves nothing", !pickerOpen && agents.later == nil)
            await send("SessionEnd", "s12")

            // 13. Claude Code outside T3: who typed a prompt comes from its transcript (Claude Code writes it just after
            // the hook); a request is answered only when its own tool call gets a result.
            let t15 = transcript("s15.jsonl"), t16 = transcript("s16.jsonl")
            Agent.testFrontmost = "com.apple.Preview" // no key press, another app in front: the old rule would say "not you"
            await send("UserPromptSubmit", "s15", ["session_title": "Terminal", "prompt_id": "p15", "transcript_path": t15.path])
            append(t15, #"{"type":"user","promptId":"p15","entrypoint":"cli","origin":{"kind":"human"},"message":{"content":"go"},"timestamp":"NOW"}"#)
            await wait(3) { agents.runs["s15"] != nil }
            check("terminal: a prompt you typed is yours, without a key press", agents.runs["s15"]?.yours == true)
            await wait(6) { pickerOpen }
            check("terminal: its nudge fires", pickerOpen)
            Windows.closePicker()
            Agent.testFrontmost = host
            Agent.testInputAge = 1 // you're typing in the terminal when something else sends a prompt there
            await send("UserPromptSubmit", "s16", ["session_title": "Queued", "prompt_id": "p16", "transcript_path": t16.path])
            append(t16, #"{"type":"user","promptId":"p16","entrypoint":"cli","origin":{"kind":"channel"},"message":{"content":"x"},"timestamp":"NOW"}"#)
            await wait(3) { agents.runs["s16"] != nil }
            Agent.testInputAge = 60
            check("terminal: a prompt you didn't type isn't yours, even while you type", agents.runs["s16"]?.yours == false)
            append(t15, #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"a1","name":"Bash","input":{"command":"ls"}},{"type":"tool_use","id":"a2","name":"Bash","input":{"command":"rm -rf build","description":"clean"}}]},"timestamp":"NOW"}"#)
            await send("PermissionRequest", "s15", ["tool_name": "Bash", "tool_input": ["description": "clean", "command": "rm -rf build"]])
            check("terminal: a request needs you", agents.runs["s15"]?.state == .needsYou)
            append(t15, #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"a1","content":"files"}]},"timestamp":"NOW"}"#)
            await wait(3)
            check("terminal: another call's result doesn't answer the request", agents.runs["s15"]?.state == .needsYou)
            append(t15, #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"a2","content":"done"}]},"timestamp":"NOW"}"#)
            await wait(4) { agents.runs["s15"]?.state == .working }
            check("terminal: its own call's result answers it within seconds", agents.runs["s15"]?.state == .working)
            await send("SessionEnd", "s15")
            await send("SessionEnd", "s16")

            // 12. T3 Code's own records: exact, for any provider, and they replace the hooks for T3's chats.
            var db: OpaquePointer?
            sqlite3_open(T3.Reader.file, &db)
            func sql(_ q: String) { if sqlite3_exec(db, q, nil, nil, nil) != SQLITE_OK { NSLog("TaskDock agent E2E: SQL \(String(cString: sqlite3_errmsg(db)))") } }
            let now = { T3.Reader.now() }
            func thread(_ id: String, _ title: String) {
                sql("INSERT INTO orchestration_v2_projection_threads VALUES ('\(id)', '\(title)', '\(now())', NULL, '{\"lastVisitedAt\":\"\(now())\"}')")
            }
            func run(_ id: String, _ thread: String, _ n: Int, by: String) {
                sql("""
                    INSERT INTO orchestration_v2_projection_messages VALUES ('m\(id)', '\(thread)', '{"createdBy":"\(by)","creationSource":"\(by == "user" ? "web" : "mcp")"}');
                    INSERT INTO orchestration_v2_projection_runs VALUES ('\(id)', '\(thread)', \(n), 'codex', 'running', '\(now())', NULL, '{"userMessageId":"m\(id)"}')
                    """)
            }
            func end(_ run: String) { sql("UPDATE orchestration_v2_projection_runs SET status = 'completed', completed_at = '\(now())' WHERE run_id = '\(run)'") }
            let poll = 3.0 // T3 is read every 2 s
            store.claudeConnected = true // reading T3 is part of "Connect Claude Code…"
            sql(T3.Reader.schema)
            await wait(poll) { T3.shared.available }
            check("T3 database read", T3.shared.available)
            thread("X", "Codex chat")
            run("X1", "X", 1, by: "user") // sent with the Send button: no key press
            await wait(poll) { agents.runs["X"] != nil }
            let x = agents.runs["X"]
            check("T3: a prompt sent with a click is yours", x?.yours == true && x?.template == coding.id && x?.host == T3.app)
            check("T3: a Codex chat protects T3 Code", agents.hosts.contains(T3.app))
            await wait(6) { pickerOpen }
            check("T3: its nudge fires", pickerOpen)
            Windows.closePicker()
            thread("Y", "Delegate")
            sql("INSERT INTO orchestration_v2_projection_subagents VALUES ('d1', 'X', 'Y', 'app_owned', 'running', '\(now())', NULL, '{}')")
            Agent.testInputAge = 1 // you're typing when the delegate's chat starts
            run("Y1", "Y", 1, by: "agent")
            end("X1")
            await wait(poll)
            Agent.testInputAge = 60
            check("T3: a delegate's chat isn't yours", agents.runs["Y"]?.yours == false)
            check("T3: the chat keeps working while its delegate is out", agents.runs["X"]?.state == .working && finished("Codex chat") == 0)
            sql("INSERT INTO orchestration_v2_projection_runtime_requests VALUES ('q1', 'Y', 'command', 'pending', '\(now())', '{}')")
            await wait(poll) { agents.runs["Y"]?.state == .needsYou }
            check("T3: an approval request needs you", agents.runs["Y"]?.state == .needsYou && needsYou("Delegate"))
            sql("UPDATE orchestration_v2_projection_runtime_requests SET status = 'resolved'")
            await wait(poll) { agents.runs["Y"]?.state == .working }
            check("T3: an answered approval is working again", agents.runs["Y"]?.state == .working)
            end("Y1")
            sql("UPDATE orchestration_v2_projection_subagents SET status = 'completed', completion_delivery_state = 'delivered'")
            run("X2", "X", 2, by: "agent") // the report wakes the chat
            await wait(poll)
            check("T3: the report's wake-up continues the run", agents.runs["X"]?.state == .working && agents.runs["X"]?.since == x?.since)
            end("X2")
            await wait(poll) { finished("Codex chat") > 0 }
            check("T3: finishes once its delegate reported", agents.runs["X"]?.state == .finished && finished("Codex chat") == 1)
            check("T3: delegate's chat finishing stays silent", finished("Delegate") == 0)
            // Background work, as T3 records it for any provider.
            thread("Z", "Background")
            run("Z1", "Z", 1, by: "user")
            await wait(6) { pickerOpen }
            Windows.closePicker()
            func tasks(_ json: String) {
                sql("INSERT OR REPLACE INTO orchestration_v2_projection_provider_threads VALUES ('pz', 'Z', 1, '{\"pendingBackgroundTasks\":\(json)}')")
            }
            tasks(#"[{"taskId":"t","kind":"command","awaited":true}]"#)
            end("Z1")
            await wait(poll)
            check("T3: work the agent waits on keeps it working, uncapped",
                  agents.runs["Z"]?.state == .working && agents.runs["Z"]?.delegatesSince != nil && finished("Background") == 0)
            tasks(#"[{"taskId":"t","kind":"command"}]"#)
            await wait(poll)
            check("T3: a plain command keeps it working, capped",
                  agents.runs["Z"]?.state == .working && agents.runs["Z"]?.delegatesSince == nil && agents.runs["Z"]?.waitingSince != nil)
            tasks("[]")
            await wait(poll) { finished("Background") > 0 }
            check("T3: finishes when its background work ends", agents.runs["Z"]?.state == .finished && finished("Background") == 1)
            // Seen per chat: T3 in front showing another chat doesn't clear it; opening it does.
            Agent.testFrontmost = T3.app
            sql("UPDATE orchestration_v2_projection_threads SET updated_at = '\(now())', payload_json = '{\"lastVisitedAt\":\"\(now())\"}' WHERE thread_id = 'Y'")
            await wait(poll)
            agents.tick(Date())
            check("T3: another chat on screen doesn't mark it seen", agents.runs["X"]?.seen == false)
            sql("UPDATE orchestration_v2_projection_threads SET updated_at = '\(now())', payload_json = '{\"lastVisitedAt\":\"\(now())\"}' WHERE thread_id = 'X'")
            await wait(poll)
            agents.tick(Date())
            check("T3: opening the chat marks it seen", agents.runs["X"]?.seen == true)
            Agent.testFrontmost = host
            // A Claude session T3 runs: its hook events are T3's, not counted twice.
            sql("INSERT INTO orchestration_v2_projection_provider_threads VALUES ('p1', 'X', NULL, '{\"nativeThreadRef\":{\"nativeId\":\"s13\"}}')")
            await send("UserPromptSubmit", "s13", ["session_title": "Codex chat"])
            check("T3: hook events for its chats are ignored", agents.runs["s13"] == nil)
            // T3 unreadable (a schema change): the hooks take over, nothing breaks.
            sql("DROP TABLE orchestration_v2_projection_subagents")
            await wait(poll) { !T3.shared.available }
            Agent.testInputAge = 1
            await send("UserPromptSubmit", "s14", ["session_title": "Fallback"])
            Agent.testInputAge = 60
            check("T3 unreadable: hooks take over", !T3.shared.available && agents.runs["s14"]?.yours == true)
            await send("SessionEnd", "s14")
            sqlite3_close(db)
            store.finish(note: "")
            await wait(8) { !Snapshot.isRunning(textEdit) }

            Snapshot.running(textEdit).forEach { $0.terminate() }
            let report: [String: Any] = ["checks": checks, "passed": checks.values.allSatisfy { $0 }, "notifications": Agent.sent]
            if let d = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? d.write(to: URL(fileURLWithPath: out))
            }
            NSApp.terminate(nil)
        }
        #endif
    }
}
