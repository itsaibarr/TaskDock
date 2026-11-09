import SQLite3
import XCTest
@testable import TaskDock

final class ModelTests: XCTestCase {
    func testBrowsersAreDetected() {
        XCTAssertTrue(AppRef(bundleID: "com.apple.Safari", name: "Safari", path: "/Applications/Safari.app").isBrowser)
        XCTAssertFalse(AppRef(bundleID: "com.apple.Notes", name: "Notes", path: "/System/Applications/Notes.app").isBrowser)
    }

    func testElapsed() {
        let start = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(elapsedText(since: start, now: start.addingTimeInterval(59)), "0m")
        XCTAssertEqual(elapsedText(since: start, now: start.addingTimeInterval(25 * 60)), "25m")
        XCTAssertEqual(elapsedText(since: start, now: start.addingTimeInterval(65 * 60)), "1h 05m")
    }

    func testDockTileMatchesDockFormat() throws {
        let tile = Dock.tile(AppRef(bundleID: "net.imput.helium", name: "Helium", path: "/Applications/Helium.app"))
        XCTAssertEqual(tile["tile-type"] as? String, "file-tile")
        let data = try XCTUnwrap(tile["tile-data"] as? [String: Any])
        XCTAssertEqual(data["bundle-identifier"] as? String, "net.imput.helium")
        let file = try XCTUnwrap(data["file-data"] as? [String: Any])
        XCTAssertEqual(file["_CFURLString"] as? String, "file:///Applications/Helium.app/")
        XCTAssertNoThrow(try PropertyListSerialization.data(fromPropertyList: [tile], format: .binary, options: 0))
    }

    func testSessionRoundTrips() throws {
        let s = Session(template: Template(name: "Writing"), goal: "Draft intro", visibleApps: ["a"], dock: Data([1, 2]))
        let back = try JSONDecoder().decode(Session.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back.goal, "Draft intro")
        XCTAssertEqual(back.dock, Data([1, 2]))
    }

    func testOldTemplatesWithoutResumeStillLoad() throws {
        let json = #"[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Math","emoji":"🧠","apps":[],"startShortcut":"","endShortcut":"","lastStopNote":""}]"#
        let t = try JSONDecoder().decode([Template].self, from: Data(json.utf8))
        XCTAssertNil(t[0].resume)
    }

    func testObsidianActiveNote() {
        let ws = #"{"main":{"children":[{"children":[{"id":"a","type":"leaf","state":{"type":"markdown","state":{"file":"Old.md"}}},{"id":"b","type":"leaf","state":{"type":"markdown","state":{"file":"Math/Week 3.md"}}}]}]},"left":{"children":[{"id":"x","type":"leaf","state":{"type":"file-explorer","state":{}}}]},"active":"b","lastOpenFiles":["Recent.md"]}"#
        XCTAssertEqual(Snapshot.activeFile(Data(ws.utf8)), "Math/Week 3.md")
        // Sidebar focused: fall back to the most recently opened file.
        XCTAssertEqual(Snapshot.activeFile(Data(ws.replacingOccurrences(of: #""active":"b""#, with: #""active":"x""#).utf8)), "Recent.md")
    }

    func testResumeItemTitles() {
        XCTAssertEqual(Resume.Item(app: "com.apple.Preview", url: URL(fileURLWithPath: "/Books/Calculus.pdf")).title, "Calculus")
        XCTAssertEqual(Resume.Item(app: "md.obsidian", url: Snapshot.obsidianLink("/Vault/Math/Week 3.md")).title, "Week 3")
    }

    func testAeroSpaceWindowList() {
        let w = AeroSpace.parse("95536|md.obsidian|2\n95537|com.apple.Preview|3\n1|x|\n")
        XCTAssertEqual(w, [.init(id: "95536", app: "md.obsidian", workspace: "2"), .init(id: "95537", app: "com.apple.Preview", workspace: "3")])
    }

    func testPhiSpaceMatchesTemplateNameUnlessChosen() {
        let spaces = [Phi.Space(id: "a", title: "Default"), Phi.Space(id: "b", title: "further math")]
        var t = Template(name: "Further Math")
        XCTAssertEqual(Phi.space(for: t, in: spaces)?.id, "b")
        t.phiSpace = "Default"
        XCTAssertEqual(Phi.space(for: t, in: spaces)?.id, "a")
    }

    func testPhiNewSpaceMenuItem() {
        XCTAssertTrue(Phi.isNewSpace("New Space"))
        XCTAssertTrue(Phi.isNewSpace("Create a New Space…"))
        XCTAssertFalse(Phi.isNewSpace("New Incognito Space"))
        XCTAssertFalse(Phi.isNewSpace("New Tab"))
    }

    func testAgentHookEvent() {
        let json = #"{"session_id":"abc","hook_event_name":"Stop","cwd":"/tmp","prompt":"secret","background_tasks":[{"id":"1"}]}"#
        var e = Agent.event(Data(json.utf8))
        e?["host"] = nil // the app this test runs under (T3 Code, Terminal, Xcode…)
        XCTAssertEqual(e, ["event": "Stop", "session": "abc", "cwd": "/tmp", "background": "1"])
        XCTAssertNil(Agent.event(Data("not json".utf8)))
        // A wake-up is flagged; the prompt text itself never leaves the hook.
        let wake = #"{"session_id":"w","hook_event_name":"UserPromptSubmit","prompt":"<task-notification>\n<task-id>x"}"#
        XCTAssertEqual(Agent.event(Data(wake.utf8))?["automatic"], "1")
        XCTAssertNil(Agent.event(Data(wake.utf8))?["prompt"])
        XCTAssertNil(Agent.event(Data(#"{"session_id":"w","hook_event_name":"UserPromptSubmit","prompt":"fix the bug"}"#.utf8))?["automatic"])
        // The prompt's id (to look up who wrote it), and a request's tool call as a fingerprint, never its input.
        XCTAssertEqual(Agent.event(Data(#"{"session_id":"w","hook_event_name":"UserPromptSubmit","prompt_id":"p1","prompt":"x"}"#.utf8))?["promptId"], "p1")
        let ask = Agent.event(Data(#"{"session_id":"w","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"rm -rf build","description":"clean"}}"#.utf8))
        XCTAssertEqual(ask?["ask"], Agent.call("Bash", ["description": "clean", "command": "rm -rf build"])) // key order doesn't matter
        XCTAssertFalse(ask?.values.contains { $0.contains("rm -rf") } ?? true)
        XCTAssertNotEqual(Agent.call("Bash", ["command": "ls"]), Agent.call("Bash", ["command": "pwd"]))
    }

    private func ctx(_ t: TimeInterval, task: UUID? = nil, input: TimeInterval = 1) -> Agent.Context {
        Agent.Context(now: Date(timeIntervalSince1970: t), task: task, goal: "g", inputAge: input, frontmost: "com.t3tools.t3code")
    }

    func testAgentSeveralChatsEachNudgeAndNotify() {
        var runs: [String: Agent.Run] = [:]
        let task = UUID()
        XCTAssertEqual(Agent.apply(.init(name: "UserPromptSubmit", session: "a", title: "[A.md](A.md)", host: "com.t3tools.t3code"), to: &runs, ctx(0, task: task)),
                       [.nudgeLater("a", Date(timeIntervalSince1970: 0))])
        XCTAssertEqual(Agent.apply(.init(name: "UserPromptSubmit", session: "b", cwd: "/x/proj"), to: &runs, ctx(5, task: task)),
                       [.nudgeLater("b", Date(timeIntervalSince1970: 5))])
        XCTAssertEqual(runs["a"]?.title, "A.md")
        XCTAssertEqual(runs["b"]?.title, "proj")
        XCTAssertEqual(runs["a"]?.host, "com.t3tools.t3code")
        XCTAssertEqual(Agent.apply(.init(name: "Stop", session: "a"), to: &runs, ctx(60)), [.notify("a", .finished)])
        XCTAssertEqual(runs["a"]?.took, 60) // the banner says how long it ran
        XCTAssertEqual([30, 23 * 60, 65 * 60, 120 * 60].map { Agent.done(after: $0) },
                       ["Done in under a minute", "Done after 23 min", "Done after 1 h 5 min", "Done after 2 h"])
        XCTAssertEqual(runs["b"]?.state, .working)
        XCTAssertEqual(Agent.apply(.init(name: "PermissionRequest", session: "b"), to: &runs, ctx(70)), [.notify("b", .needsYou)])
        XCTAssertEqual(Agent.apply(.init(name: "PostToolUse", session: "b"), to: &runs, ctx(80)), [])
        XCTAssertEqual(runs["b"]?.state, .working)
        XCTAssertEqual(Agent.apply(.init(name: "SessionEnd", session: "b"), to: &runs, ctx(90)), [])
        XCTAssertNil(runs["b"])
    }

    func testAgentPromptsYouDidntSendStaySilent() {
        var runs: [String: Agent.Run] = [:]
        let task = UUID(), other = UUID()
        // A sub-thread or scheduled task: no key or click just before it.
        XCTAssertEqual(Agent.apply(.init(name: "UserPromptSubmit", session: "c"), to: &runs, ctx(0, task: task, input: 60)), [])
        XCTAssertEqual(runs["c"]?.state, .working) // still tracked, so its app is never quit
        XCTAssertNil(runs["c"]?.template) // and it parks no task
        XCTAssertEqual(Agent.apply(.init(name: "Stop", session: "c"), to: &runs, ctx(30)), [])
        // You're typing in Preview when a chat in T3 starts on its own: not yours.
        XCTAssertEqual(Agent.apply(.init(name: "UserPromptSubmit", session: "p", host: "com.t3tools.t3code"), to: &runs,
                                   Agent.Context(now: Date(), task: task, goal: "", inputAge: 1, frontmost: "com.apple.Preview")), [])
        // But if it then asks you something, you hear about it: it blocks your work.
        XCTAssertEqual(Agent.apply(.init(name: "PermissionRequest", session: "p"), to: &runs, ctx(5)), [.notify("p", .needsYou)])
        // A chat you started stays yours and stays with its task: its wake-ups (background work done,
        // sub-threads reporting back) and queued messages are your work, even while you're in another task.
        _ = Agent.apply(.init(name: "UserPromptSubmit", session: "d", host: "com.t3tools.t3code"), to: &runs, ctx(0, task: task))
        _ = Agent.apply(.init(name: "Stop", session: "d"), to: &runs, ctx(100))
        XCTAssertEqual(Agent.apply(.init(name: "UserPromptSubmit", session: "d"), to: &runs, ctx(900, task: other, input: 600)), [])
        XCTAssertEqual(runs["d"]?.yours, true) // no nudge for a wake-up, but its finish still notifies
        XCTAssertEqual(Agent.apply(.init(name: "Stop", session: "d"), to: &runs, ctx(950)), [.notify("d", .finished)])
        XCTAssertEqual(runs["d"]?.template, task)
        XCTAssertEqual(runs["d"]?.host, "com.t3tools.t3code")
        _ = Agent.apply(.init(name: "UserPromptSubmit", session: "a", title: "Chat A"), to: &runs, ctx(950))
        _ = Agent.apply(.init(name: "UserPromptSubmit", session: "a", cwd: "/x/proj"), to: &runs, ctx(960))
        XCTAssertEqual(runs["a"]?.title, "Chat A") // a wake-up without a title keeps the chat's
        // You're typing in chat A of T3 when chat D wakes up: not sent by you, so no nudge and it stays put.
        XCTAssertEqual(Agent.apply(.init(name: "UserPromptSubmit", session: "d", host: "com.t3tools.t3code", automatic: true),
                                   to: &runs, ctx(990, task: other)), [])
        XCTAssertEqual(runs["d"]?.template, task)
        // Delegates still out: their turn's start carries over wake-ups and your follow-ups; a finishing Stop clears it.
        let turn = Date(timeIntervalSince1970: 2000)
        _ = Agent.apply(.init(name: "UserPromptSubmit", session: "g", host: "com.t3tools.t3code"), to: &runs, ctx(2000))
        var out = Agent.Event(name: "Stop", session: "g", background: true)
        out.delegates = true // the app found delegates still out
        _ = Agent.apply(out, to: &runs, ctx(2030))
        _ = Agent.apply(.init(name: "UserPromptSubmit", session: "g", automatic: true), to: &runs, ctx(2090))
        XCTAssertEqual(runs["g"]?.delegatesSince, turn)
        XCTAssertEqual(runs["g"]?.since, turn) // a wake-up mid-wait keeps the run's start (and its nudge)
        _ = Agent.apply(.init(name: "UserPromptSubmit", session: "g", host: "com.t3tools.t3code"), to: &runs, ctx(2100))
        XCTAssertEqual(runs["g"]?.delegatesSince, turn) // your follow-up doesn't drop delegates still out
        XCTAssertEqual(Agent.expire(&runs, now: Date(timeIntervalSince1970: 2100 + 31 * 60)), []) // no 30-min cap for delegates
        XCTAssertEqual(runs["g"]?.state, .working)
        _ = Agent.apply(.init(name: "Stop", session: "g"), to: &runs, ctx(2200))
        XCTAssertNil(runs["g"]?.delegatesSince)
        // A run that keeps waking up for hours lives on; 3 hours after its last event it's forgotten.
        _ = Agent.apply(.init(name: "UserPromptSubmit", session: "h", host: "com.t3tools.t3code"), to: &runs, ctx(0))
        for hour in 1...4 {
            _ = Agent.apply(.init(name: "Stop", session: "h", background: true), to: &runs, ctx(Double(hour) * 3600 - 60))
            _ = Agent.apply(.init(name: "UserPromptSubmit", session: "h", automatic: true), to: &runs, ctx(Double(hour) * 3600))
        }
        _ = Agent.expire(&runs, now: Date(timeIntervalSince1970: 4.5 * 3600))
        XCTAssertEqual(runs["h"]?.state, .working)
        XCTAssertEqual(runs["h"]?.since, Date(timeIntervalSince1970: 0))
        _ = Agent.expire(&runs, now: Date(timeIntervalSince1970: 7.1 * 3600))
        XCTAssertNil(runs["h"])
        // Sending it a new prompt yourself from another task moves it there.
        _ = Agent.apply(.init(name: "UserPromptSubmit", session: "d", host: "com.t3tools.t3code"), to: &runs, ctx(1000, task: other))
        XCTAssertEqual(runs["d"]?.template, other)
    }

    func testAgentBackgroundWorkAndLateEvents() {
        var runs: [String: Agent.Run] = [:]
        _ = Agent.apply(.init(name: "UserPromptSubmit", session: "e"), to: &runs, ctx(0))
        XCTAssertEqual(Agent.apply(.init(name: "Stop", session: "e", background: true), to: &runs, ctx(10)), [])
        XCTAssertEqual(runs["e"]?.state, .working)
        XCTAssertEqual(Agent.apply(.init(name: "Stop", session: "e"), to: &runs, ctx(20)), [.notify("e", .finished)])
        // A turn left waiting on a server that never ends counts as finished after 30 minutes.
        _ = Agent.apply(.init(name: "UserPromptSubmit", session: "f"), to: &runs, ctx(0))
        _ = Agent.apply(.init(name: "Stop", session: "f", background: true), to: &runs, ctx(10))
        XCTAssertEqual(Agent.expire(&runs, now: Date(timeIntervalSince1970: 1500)), [])
        XCTAssertEqual(Agent.expire(&runs, now: Date(timeIntervalSince1970: 1900)), [.notify("f", .finished)])
        XCTAssertEqual(runs["f"]?.state, .finished)
        // "Waiting for your input" after a finished turn doesn't turn it into needs-you.
        XCTAssertEqual(Agent.apply(.init(name: "Notification", session: "e"), to: &runs, ctx(80)), [])
        XCTAssertEqual(runs["e"]?.state, .finished)
        // Events for chats TaskDock never saw start (it was launched mid-run) are ignored.
        XCTAssertEqual(Agent.apply(.init(name: "Stop", session: "zz"), to: &runs, ctx(90)), [])
        XCTAssertNil(runs["zz"])
    }

    func testAgentTranscriptReader() {
        let line = { (type: String, text: String, ts: String) in
            #"{"type":"\#(type)","message":{"content":[{"type":"text","text":"\#(text)"}]},"timestamp":"\#(ts)"}"#
        }
        var d = Agent.Delegates()
        // The last message is your interrupt; the newest message time comes back too.
        let r = Agent.read([line("assistant", "working", "2026-11-08T10:01:00.000Z"),
                            line("user", "[Request interrupted by user]", "2026-11-08T10:02:00.000Z"),
                            #"{"type":"api-request","x":1}"#].joined(separator: "\n"), &d)
        XCTAssertTrue(r.interrupted)
        XCTAssertEqual(r.latest, ISO8601DateFormatter().date(from: "2026-11-08T10:02:00Z"))
        XCTAssertFalse(Agent.read(line("assistant", "done", "2026-11-08T10:03:00.000Z"), &d).interrupted)
        // A tool result that merely quotes the marker (an agent reading this code) isn't an interrupt.
        let quoted = #"{"type":"user","message":{"content":[{"type":"tool_result","content":"if text == [Request interrupted by user]"}]},"timestamp":"2026-11-08T10:05:00.000Z"}"#
        XCTAssertFalse(Agent.read(quoted, &d).interrupted)
        // Delegates: out from the call until the report, counted across reads (council starts two).
        let call = { (id: String, mode: String) in
            #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"\#(id)","name":"mcp__t3-code__delegate_task","input":{"task":"review","mode":"\#(mode)"}}]},"timestamp":"2026-11-08T10:01:00.000Z"}"#
        }
        let result = { (id: String, text: String, error: Bool) in
            #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"\#(id)","is_error":\#(error),"content":"\#(text)"}]},"timestamp":"2026-11-08T10:01:30.000Z"}"#
        }
        let report = #"{"type":"user","message":{"role":"user","content":"Delegated task node:x (Council) [completed]:\nok"},"timestamp":"2026-11-08T10:10:00.000Z"}"#
        _ = Agent.read([call("a", "async"), result("a", "started", false), call("b", "async"), result("b", "started", false)].joined(separator: "\n"), &d)
        XCTAssertEqual(d.open, 2)
        _ = Agent.read(report, &d)
        XCTAssertEqual(d.open, 1)
        _ = Agent.read(report, &d)
        XCTAssertEqual(d.open, 0)
        // One that failed to start, and a `mode: wait` one that answered in place, were never out.
        _ = Agent.read([call("c", "async"), result("c", "unavailable", true), call("w", "wait"), result("w", "done", false)].joined(separator: "\n"), &d)
        XCTAssertEqual(d.open, 0)
        XCTAssertEqual(d.calls, [:])
        // A wait that timed out stays out until its report wakes the chat.
        _ = Agent.read([call("t", "wait"), result("t", "{waitTimedOut: true}", false)].joined(separator: "\n"), &d)
        XCTAssertEqual(d.open, 1)
        _ = Agent.read(report, &d)
        XCTAssertEqual(d.open, 0)
        // The calls whose results came, to tell which request was answered (allowed or denied).
        let tool = { (id: String, cmd: String) in
            #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"\#(id)","name":"Bash","input":{"command":"\#(cmd)"}}]},"timestamp":"2026-11-08T10:20:00.000Z"}"#
        }
        let asked = Agent.call("Bash", ["command": "rm -rf build"])
        XCTAssertEqual(Agent.read([tool("x", "ls"), tool("y", "rm -rf build")].joined(separator: "\n"), &d).results, [])
        XCTAssertEqual(Set(d.tools?.values ?? [:].values), [Agent.call("Bash", ["command": "ls"]), asked])
        XCTAssertEqual(Agent.read(result("x", "files", false), &d).results, [Agent.call("Bash", ["command": "ls"])])
        XCTAssertEqual(Agent.read(result("y", "The user doesn't want to proceed", true), &d).results, [asked])
        XCTAssertEqual(d.tools, [:])
    }

    func testAgentWhoTypedAPrompt() {
        let line = { (entry: String, origin: String?) in
            #"{"type":"user","promptId":"p1","entrypoint":"\#(entry)","message":{"content":"hi p1"}\#(origin.map { #","origin":{"kind":"\#($0)"}"# } ?? "")}"#
        }
        XCTAssertEqual(Agent.typed(line("cli", "human"), prompt: "p1"), true) // typed in a terminal
        XCTAssertEqual(Agent.typed(line("cli", "task-notification"), prompt: "p1"), false) // a wake-up
        XCTAssertNil(Agent.typed(line("cli", nil), prompt: "p1")) // an older Claude Code: key presses decide
        XCTAssertNil(Agent.typed(line("sdk-ts", "human"), prompt: "p1")) // a script or T3: key presses decide
        XCTAssertNil(Agent.typed(line("cli", "human"), prompt: "p2")) // not written yet
        XCTAssertNil(Agent.typed(#"{"type":"assistant","promptId":"p1","entrypoint":"cli","origin":{"kind":"human"}}"#, prompt: "p1"))
        XCTAssertEqual(Agent.typed(line("cli", nil) + "\n" + line("cli", "human"), prompt: "p1"), true) // a meta line comes first
    }

    func testAgentExactEvents() {
        var runs: [String: Agent.Run] = [:]
        let task = UUID()
        // T3 says you sent it (Send button, dictation): yours and nudged, with no key press at all.
        var e = Agent.Event(name: "UserPromptSubmit", session: "t", title: "Chat", host: T3.app)
        e.sent = true
        XCTAssertEqual(Agent.apply(e, to: &runs, ctx(0, task: task, input: 600)), [.nudgeLater("t", Date(timeIntervalSince1970: 0))])
        XCTAssertEqual(runs["t"]?.template, task)
        // A delegate's chat started while you type: T3 says it isn't yours.
        var child = Agent.Event(name: "UserPromptSubmit", session: "c", host: T3.app, automatic: true)
        child.sent = false
        XCTAssertEqual(Agent.apply(child, to: &runs, ctx(5, task: task, input: 0)), [])
        XCTAssertEqual(runs["c"]?.yours, false)
        // The turn ends with delegates out: still working, no banner, no time cap.
        var stop = Agent.Event(name: "Stop", session: "t")
        stop.delegates = true
        XCTAssertEqual(Agent.apply(stop, to: &runs, ctx(60)), [])
        XCTAssertEqual(runs["t"]?.state, .working)
        XCTAssertEqual(runs["t"]?.delegatesSince, Date(timeIntervalSince1970: 0))
        XCTAssertEqual(Agent.expire(&runs, now: Date(timeIntervalSince1970: 3000)), [])
        // The report wakes it: the same run goes on (its start and nudge kept); then it finishes.
        var wake = Agent.Event(name: "UserPromptSubmit", session: "t", host: T3.app, automatic: true)
        wake.sent = false
        XCTAssertEqual(Agent.apply(wake, to: &runs, ctx(3100, input: 0)), [])
        XCTAssertEqual(runs["t"]?.since, Date(timeIntervalSince1970: 0))
        XCTAssertEqual(Agent.apply(.init(name: "Stop", session: "t"), to: &runs, ctx(3200)), [.notify("t", .finished)])
        // An approval answered: working again at once. An interrupt: done and seen, quietly.
        _ = Agent.apply(e, to: &runs, ctx(4000))
        _ = Agent.apply(.init(name: "PermissionRequest", session: "t"), to: &runs, ctx(4010))
        XCTAssertEqual(Agent.apply(.init(name: "Resume", session: "t"), to: &runs, ctx(4020)), [])
        XCTAssertEqual(runs["t"]?.state, .working)
        XCTAssertEqual(Agent.apply(.init(name: "Interrupt", session: "t"), to: &runs, ctx(4030)), [])
        XCTAssertEqual(runs["t"]?.state, .finished)
        XCTAssertEqual(runs["t"]?.seen, true)
        XCTAssertEqual(runs["t"]?.yours, true)
        // Delegates back but a plain command still runs: working, now with the 30-minute cap.
        _ = Agent.apply(e, to: &runs, ctx(5000))
        _ = Agent.apply(stop, to: &runs, ctx(5010))
        var bg = Agent.Event(name: "Stop", session: "t")
        bg.background = true
        XCTAssertEqual(Agent.apply(bg, to: &runs, ctx(5020)), [])
        XCTAssertNil(runs["t"]?.delegatesSince)
        XCTAssertEqual(Agent.expire(&runs, now: Date(timeIntervalSince1970: 5020 + 31 * 60)), [.notify("t", .finished)])
        // A request remembers which call it asks about until you answer.
        _ = Agent.apply(e, to: &runs, ctx(9000))
        var ask = Agent.Event(name: "PermissionRequest", session: "t")
        ask.ask = "Bash:1"
        _ = Agent.apply(ask, to: &runs, ctx(9010))
        XCTAssertEqual(runs["t"]?.ask, "Bash:1")
        _ = Agent.apply(.init(name: "Resume", session: "t"), to: &runs, ctx(9020))
        XCTAssertNil(runs["t"]?.ask)
    }

    private func chat(_ run: String, _ status: String, sent: Bool = true, needsYou: Bool = false, delegates: Bool = false,
                      holds: Bool = false, background: Bool = false) -> T3.Chat {
        T3.Chat(run: run, status: status, sent: sent, title: "Chat", needsYou: needsYou, delegates: delegates, holds: holds, background: background)
    }

    private func names(_ r: [Agent.Event]) -> [String] {
        r.map { "\($0.session):\($0.name)\($0.sent.map { $0 ? "+sent" : "-sent" } ?? "")\($0.delegates ? "+delegates" : "")\($0.background ? "+background" : "")" }
    }

    func testT3ChatChangesBecomeEvents() {
        let ev = { (old: [String: T3.Chat]?, new: [String: T3.Chat]) in self.names(T3.events(from: old, to: new)) }
        // First read after launch: chats already working are tracked, not taken as sent; finished ones are told.
        XCTAssertEqual(ev(nil, ["a": chat("a1", "running"), "b": chat("b1", "completed")]), ["a:UserPromptSubmit-sent", "b:Stop"])
        // A new run you sent, then its end.
        XCTAssertEqual(ev(["a": chat("a1", "completed")], ["a": chat("a2", "running")]), ["a:UserPromptSubmit+sent"])
        XCTAssertEqual(ev(["a": chat("a2", "running")], ["a": chat("a2", "completed")]), ["a:Stop"])
        XCTAssertEqual(ev([:], ["n": chat("n1", "completed")]), ["n:UserPromptSubmit+sent", "n:Stop"]) // too quick to see running
        XCTAssertEqual(ev(["a": chat("a2", "running")], ["a": chat("a2", "running")]), [])
        // Delegates out at the turn's end; the report's wake-up; the end.
        XCTAssertEqual(ev(["a": chat("a2", "running")], ["a": chat("a2", "completed", delegates: true)]), ["a:Stop+delegates"])
        XCTAssertEqual(ev(["a": chat("a2", "completed", delegates: true)], ["a": chat("a3", "running", sent: false)]), ["a:UserPromptSubmit-sent"])
        XCTAssertEqual(ev(["a": chat("a2", "completed", delegates: true)], ["a": chat("a2", "completed")]), ["a:Stop"])
        // Questions and approvals; interrupts.
        XCTAssertEqual(ev(["a": chat("a2", "running")], ["a": chat("a2", "running", needsYou: true)]), ["a:PermissionRequest"])
        XCTAssertEqual(ev(["a": chat("a2", "running", needsYou: true)], ["a": chat("a2", "running")]), ["a:Resume"])
        XCTAssertEqual(ev(["a": chat("a2", "running")], ["a": chat("a2", "interrupted")]), ["a:Interrupt"])
        XCTAssertEqual(ev(["a": chat("a2", "running")], [:]), ["a:SessionEnd"]) // deleted in T3
        // Background work T3 records: a plain command keeps it working (capped); its end, or the agent waiting on it.
        XCTAssertEqual(ev(["c": chat("c1", "running")], ["c": chat("c1", "completed", background: true)]), ["c:Stop+background"])
        XCTAssertEqual(ev(["c": chat("c1", "completed", background: true)], ["c": chat("c1", "completed")]), ["c:Stop"])
        XCTAssertEqual(ev(["c": chat("c1", "completed", background: true)], ["c": chat("c1", "completed", holds: true, background: true)]),
                       ["c:Stop+delegates"])
        // You stopped it: background work left running doesn't keep it going, a delegate still out does.
        XCTAssertEqual(ev(["c": chat("c1", "running")], ["c": chat("c1", "interrupted", holds: true, background: true)]), ["c:Interrupt"])
        XCTAssertEqual(ev(["c": chat("c1", "running")], ["c": chat("c1", "interrupted", delegates: true)]), ["c:Stop+delegates"])
        XCTAssertEqual(ev(nil, ["c": chat("c1", "completed", background: true)]), ["c:UserPromptSubmit-sent", "c:Stop+background"])
    }

    /// The real T3 database on this Mac, read-only: the reader opens it and every query runs.
    func testT3ReaderOpensLiveDatabase() throws {
        let live = NSHomeDirectory() + "/.t3/userdata/statev2.sqlite"
        try XCTSkipUnless(FileManager.default.fileExists(atPath: live), "T3 Code not installed")
        let reader = try XCTUnwrap(T3.Reader(path: live), "schema check failed against the live database")
        XCTAssertNotNil(reader.chats(now: Date()))
        XCTAssertTrue(reader.onScreen(now: Date()) != nil)
        _ = reader.thread(forSession: "none")
    }

    func testT3ReaderQueries() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("t3-\(UUID().uuidString).sqlite").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let ago = { (m: Double) in f.string(from: Date().addingTimeInterval(-m * 60)) }
        let sql = T3.Reader.schema + """
            INSERT INTO orchestration_v2_projection_threads VALUES
              ('A', '[Plan.md](Plan.md)', '\(ago(1))', NULL, '{"lastVisitedAt":"\(ago(1))"}'),
              ('B', 'Council', '\(ago(2))', NULL, '{"lastVisitedAt":"\(ago(30))"}'),
              ('C', 'Old', '\(ago(400))', NULL, '{}'),
              ('E', 'Resumed', '\(ago(2))', NULL, '{}'),
              ('F', 'Overnight', '\(ago(400))', NULL, '{}'),
              ('H', 'Long done', '\(ago(400))', NULL, '{}'),
              ('G', 'Reading', '\(ago(400))', NULL, '{"lastVisitedAt":"\(ago(0.5))"}'),
              ('I', 'Awaits', '\(ago(2))', NULL, '{}'), ('J', 'Dev server', '\(ago(2))', NULL, '{}'), ('L', 'Unknown kind', '\(ago(2))', NULL, '{}'), ('K', 'Agent team', '\(ago(400))', NULL, '{}'),
              ('D', 'Deleted', '\(ago(1))', '\(ago(1))', '{}');
            INSERT INTO orchestration_v2_projection_runs VALUES
              ('A1', 'A', 1, 'claudeAgent', 'completed', '\(ago(20))', '\(ago(19))', '{"userMessageId":"mA1"}'),
              ('A2', 'A', 2, 'claudeAgent', 'running', '\(ago(5))', NULL, '{"userMessageId":"mA2"}'),
              ('B1', 'B', 1, 'codex', 'completed', '\(ago(10))', '\(ago(9))', '{"userMessageId":"mB1"}'),
              ('C1', 'C', 1, 'codex', 'completed', '\(ago(300))', '\(ago(299))', '{}'),
              ('D1', 'D', 1, 'codex', 'running', '\(ago(5))', NULL, '{}'),
              ('E1', 'E', 1, 'claudeAgent', 'running', '\(ago(2))', NULL, '{"userMessageId":"mE1"}'),
              ('F1', 'F', 1, 'codex', 'running', '\(ago(300))', NULL, '{}'),
              ('H1', 'H', 1, 'codex', 'completed', '\(ago(300))', '\(ago(0.1))', '{}'),
              ('G1', 'G', 1, 'codex', 'completed', '\(ago(300))', '\(ago(299))', '{}'),
              ('I1', 'I', 1, 'claudeAgent', 'completed', '\(ago(5))', '\(ago(4))', '{}'),
              ('J1', 'J', 1, 'claudeAgent', 'completed', '\(ago(5))', '\(ago(4))', '{}'),
              ('K1', 'K', 1, 'opencode', 'completed', '\(ago(300))', '\(ago(290))', '{}'),
              ('L1', 'L', 1, 'muse', 'completed', '\(ago(5))', '\(ago(4))', '{}');
            INSERT INTO orchestration_v2_projection_messages VALUES
              ('mA2', 'A', '{"createdBy":"user","creationSource":"web"}'),
              ('mB1', 'B', '{"createdBy":"agent","creationSource":"provider"}'),
              ('mE1', 'E', '{"createdBy":"user","creationSource":"server"}');
            INSERT INTO orchestration_v2_projection_runtime_requests VALUES
              ('q1', 'B', 'command', 'pending', '\(ago(8))', '{}'), ('q0', 'A', 'user_input', 'resolved', '\(ago(4))', '{}');
            INSERT INTO orchestration_v2_projection_subagents VALUES
              ('s1', 'B', 'child', 'app_owned', 'completed', '\(ago(3))', 'claimed', '{}'),
              ('s2', 'A', 'child2', 'app_owned', 'completed', '\(ago(3))', 'delivered', '{}'),
              ('s3', 'A', NULL, 'provider_native', 'running', '\(ago(3))', NULL, '{}');
            INSERT INTO orchestration_v2_projection_provider_threads VALUES ('p1', 'A', 2, '{"nativeThreadRef":{"nativeId":"sess-1"}}'),
              ('p2', 'I', 1, '{"pendingBackgroundTasks":[{"taskId":"t","kind":"command","awaited":true}]}'),
              ('p3', 'J', 1, '{"pendingBackgroundTasks":[{"taskId":"t","kind":"command"},{"taskId":"m","kind":"monitor"}]}'),
              ('p4', 'K', 1, '{"pendingBackgroundTasks":[{"taskId":"t","kind":"subagent"}]}'),
              ('p6', 'L', 1, '{"pendingBackgroundTasks":[{"taskId":"t"}]}'),
              ('p5', 'H', 0, '{"pendingBackgroundTasks":[{"taskId":"t","kind":"command","awaited":true}]}'); -- an earlier provider's
            """
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK, String(cString: sqlite3_errmsg(db)))
        let reader = try XCTUnwrap(T3.Reader(path: path))
        let chats = try XCTUnwrap(reader.chats(now: Date()))
        XCTAssertEqual(Set(chats.keys), ["A", "B", "E", "F", "H", "I", "J", "K", "L"]) // C and G are old, D deleted; F and K still work, H just ended
        XCTAssertEqual(chats["I"]?.phase, .delegating) // the agent waits on its command: no time cap
        XCTAssertEqual(chats["J"]?.phase, .waiting) // a plain command or monitor: capped
        XCTAssertEqual(chats["K"]?.phase, .delegating) // a background agent, past 3 hours
        XCTAssertEqual(chats["L"]?.phase, .waiting) // work of no stated kind still counts, capped
        XCTAssertEqual(chats["H"]?.phase, .finished) // a 5-hour run that just finished still gets its Stop
        XCTAssertEqual(chats["H"]?.holds, false) // work left on an earlier provider thread doesn't hold it
        XCTAssertEqual(chats["E"]?.sent, false) // T3 resumed it by itself, nobody typed it
        XCTAssertEqual(chats["A"]?.run, "A2")
        XCTAssertEqual(chats["A"]?.sent, true)
        XCTAssertEqual(chats["A"]?.phase, .working)
        XCTAssertEqual(chats["A"]?.needsYou, false)
        XCTAssertEqual(chats["A"]?.delegates, false) // delivered, or Claude's own sub-agents
        XCTAssertEqual(chats["A"]?.title, "[Plan.md](Plan.md)")
        XCTAssertEqual(chats["B"]?.sent, false)
        XCTAssertEqual(chats["B"]?.needsYou, true)
        XCTAssertEqual(chats["B"]?.phase, .delegating)
        XCTAssertEqual(reader.onScreen(now: Date()), "G") // opened last, though opening it didn't touch updated_at
        XCTAssertEqual(reader.thread(forSession: "sess-1"), "A")
        XCTAssertNil(reader.thread(forSession: "other"))
        // A schema older than the one checked, or tables gone: not read at all.
        XCTAssertEqual(sqlite3_exec(db, "DROP TABLE orchestration_v2_projection_subagents", nil, nil, nil), SQLITE_OK)
        XCTAssertNil(reader.chats(now: Date()))
        XCTAssertEqual(sqlite3_exec(db, "DELETE FROM effect_sql_migrations", nil, nil, nil), SQLITE_OK)
        XCTAssertNil(T3.Reader(path: path))
        XCTAssertNil(T3.Reader(path: path + ".missing"))
    }

    func testClaudeHooksKeepOtherHooks() {
        let other: [String: Any] = ["hooks": [["type": "command", "command": "mine"]]]
        let settings: [String: Any] = ["model": "opus", "hooks": ["Stop": [other], "PreToolUse": [other]]]
        let on = Agent.connect(settings, command: "td")
        XCTAssertTrue(Agent.isConnected(on))
        XCTAssertEqual((on["hooks"] as? [String: Any])?["Stop"].map { ($0 as! [Any]).count }, 2)
        // An older version's PostToolUse hook makes the hooks out of date, so launch repairs them; connecting drops it.
        XCTAssertNil((on["hooks"] as? [String: Any])?["PostToolUse"])
        var older = on
        older["hooks"] = (on["hooks"] as! [String: Any]).merging(["PostToolUse": [["_taskdock": true, "matcher": "AskUserQuestion",
                                                                                   "hooks": [["type": "command", "command": "td"]]]]]) { $1 }
        XCTAssertFalse(Agent.isCurrent(older, command: "td"))
        XCTAssertNil((Agent.connect(older, command: "td")["hooks"] as? [String: Any])?["PostToolUse"])
        // Connecting twice doesn't add the hooks twice.
        XCTAssertEqual(((Agent.connect(on, command: "td")["hooks"] as? [String: Any])?["Stop"] as? [Any])?.count, 2)
        XCTAssertTrue(Agent.isCurrent(on, command: "td"))
        XCTAssertFalse(Agent.isCurrent(on, command: "moved"))
        var later = on // another tool adds a hook after TaskDock's: no rewrite needed
        later["hooks"] = (on["hooks"] as! [String: Any]).merging(["Stop": ((on["hooks"] as! [String: Any])["Stop"] as! [Any]) + [other]]) { $1 }
        XCTAssertTrue(Agent.isCurrent(later, command: "td"))
        let off = Agent.disconnect(on)
        XCTAssertFalse(Agent.isConnected(off))
        XCTAssertTrue(NSDictionary(dictionary: off).isEqual(to: settings))
        XCTAssertNil(Agent.disconnect(Agent.connect([:], command: "td"))["hooks"])
    }
}
