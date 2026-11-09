import AppKit
import CryptoKit
import UserNotifications

/// Knows when an AI agent is working. Two sources feed the same rules (`apply`): T3 Code's own records
/// (`T3`, exact, every provider) and Claude Code hooks (the fallback, e.g. Claude Code in a terminal).
/// The hook runs this same binary as `TaskDock agent`, which hands the event to the running app.
enum Agent {
    /// Dev runs use their own channel, so test events never reach the installed app.
    static let note: Notification.Name = {
        #if DEBUG
        if let c = ProcessInfo.processInfo.environment["TASKDOCK_AGENT_CHANNEL"] { return .init("com.taskdock.agent.\(c)") }
        #endif
        return .init("com.taskdock.agent")
    }()

    enum State: String, Codable { case working, finished, needsYou }

    /// One Claude Code chat's current turn.
    struct Run: Codable, Equatable {
        /// The task you were in when you sent the prompt; nil when no task was running.
        var template: UUID?
        var goal = ""
        /// The chat's title, to tell several chats apart.
        var title: String
        /// The app the chat runs in (T3 Code, Terminal…), found from the hook's parent processes; never quit while the run works.
        var host: String?
        var transcript: String?
        var state: State = .working
        var since: Date
        /// You sent this prompt (vs. a sub-thread, scheduled task or loop): only yours nudge and notify.
        var yours: Bool
        var nudged = false
        /// You've seen it finish: it leaves the menu, but the chat stays yours for its wake-ups.
        var seen = false
        // New fields need a default *and* to be optional (or a custom decoder): a key missing from an older
        // agents.json otherwise fails the whole file, and runs saved before an update would be lost.
        /// The turn ended with background work still running (a test, a server): the agent will be back.
        var waitingSince: Date?
        /// When the turn that started T3 delegates began; kept across their reports until all are back.
        var delegatesSince: Date?
        /// The chat's last event; a run silent for 3 hours is forgotten.
        var last: Date?
        /// How long the finished turn ran, for its banner.
        var took: TimeInterval?
        /// Hook path: how far the transcript has been read, and T3 delegates still out.
        var read: UInt64?
        var delegates: Delegates?
        /// Hook path: the tool call it asks you about (`Agent.call`), so only that call's result means you answered.
        var ask: String?

        /// The turn is over: nothing left to wait on, and calls it left open never get a result.
        mutating func finish(at now: Date) {
            (state, took, since, waitingSince, delegatesSince) = (.finished, now.timeIntervalSince(since), now, nil, nil)
            delegates?.tools = nil
        }
    }

    /// T3 delegates a chat started that haven't reported back, read from its transcript as it grows.
    struct Delegates: Codable, Equatable {
        var open = 0
        /// Delegate calls whose tool result hasn't come yet → `mode: wait`.
        var calls: [String: Bool] = [:]
        /// Every tool call whose result hasn't come yet → `Agent.call` of it, to find the one a request asks about.
        var tools: [String: String]?
    }

    /// A hook event, as the hook process passes it on.
    struct Event {
        var name: String
        var session: String
        var title: String?
        var cwd: String?
        var transcript: String?
        var host: String?
        /// Stop while background work (a test, a build) still runs: the agent isn't done.
        var background = false
        /// A prompt the agent's tools wrote (background work done, a sub-agent reporting back), not you.
        var automatic = false
        /// Known for sure (T3 records who wrote each prompt); nil: inferred from your last key press.
        var sent: Bool?
        /// Stop while delegates it started haven't reported back.
        var delegates = false
        /// Claude Code's id for the prompt, to look up in the transcript who wrote it.
        var prompt: String?
        /// PermissionRequest: the tool call it asks about (`Agent.call`).
        var ask: String?

        init(name: String, session: String, title: String? = nil, cwd: String? = nil, transcript: String? = nil,
             host: String? = nil, background: Bool = false, automatic: Bool = false) {
            (self.name, self.session, self.title, self.cwd, self.transcript, self.host, self.background, self.automatic)
                = (name, session, title, cwd, transcript, host, background, automatic)
        }

        init?(_ info: [AnyHashable: Any]?) {
            guard let i = info as? [String: String], let name = i["event"], let session = i["session"] else { return nil }
            self.init(name: name, session: session, title: i["title"], cwd: i["cwd"], transcript: i["transcript"],
                      host: i["host"], background: i["background"] == "1", automatic: i["automatic"] == "1")
            (prompt, ask) = (i["promptId"], i["ask"])
        }
    }

    /// What's around when an event arrives.
    struct Context {
        var now: Date
        var task: UUID?
        var goal: String
        /// Seconds since your last key press or click.
        var inputAge: TimeInterval
        var frontmost: String?
    }

    enum Effect: Equatable {
        case nudgeLater(String, Date)
        case notify(String, State)
    }

    // MARK: Rules (pure, unit-tested)

    /// Applies one hook event to the runs. Returns what the app should do about it.
    static func apply(_ e: Event, to runs: inout [String: Run], _ c: Context) -> [Effect] {
        let old = runs[e.session]
        defer { runs[e.session]?.last = c.now }
        switch e.name {
        case "UserPromptSubmit":
            // You just sent it: a key press (↩) a moment ago, with the chat's own app in front, and not a
            // wake-up (those can arrive while you type in another chat of the same app).
            let host = e.host ?? old?.host
            let sent = e.sent ?? (!e.automatic && c.inputAge < 5 && (host == nil || host == c.frontmost))
            // A chat you started stays yours: its queued messages and wake-ups (background work, sub-threads
            // reporting back) are your work too. Chats you never prompted (sub-threads, scheduled tasks) aren't.
            let yours = sent || old?.yours == true
            let continuing = !sent && e.automatic && old?.state == .working // a wake-up mid-wait: same run
            runs[e.session] = Run(template: sent ? c.task : old?.template, goal: sent ? c.goal : old?.goal ?? "",
                                  title: label(e.title, cwd: nil) ?? old?.title ?? label(nil, cwd: e.cwd) ?? "Claude Code", host: host,
                                  transcript: e.transcript ?? old?.transcript,
                                  // A wake-up mid-wait continues the same run: keep its start, so its nudge still comes.
                                  since: continuing ? old!.since : c.now, yours: yours, nudged: continuing && old!.nudged,
                                  // Delegates still out stay counted from their turn, even across a follow-up you send.
                                  delegatesSince: old?.delegatesSince, read: old?.read, delegates: old?.delegates)
            // Only a prompt you just sent starts half-waiting; a wake-up mid-task mustn't pop the picker.
            return sent ? [.nudgeLater(e.session, c.now)] : []
        case "Stop":
            guard var r = old, r.state != .finished else { return [] }
            if e.background || e.delegates { // it wakes up again when that work ends (a new prompt event)
                runs[e.session]?.waitingSince = c.now
                // Delegates (and work the agent waits on) have no time cap: each reports back, even when cancelled.
                runs[e.session]?.delegatesSince = e.delegates ? r.delegatesSince ?? r.since : nil
                return []
            }
            r.finish(at: c.now)
            runs[e.session] = r
            return r.yours ? [.notify(e.session, .finished)] : []
        case "PermissionRequest":
            guard var r = old, r.state == .working else { return [] }
            (r.state, r.ask) = (.needsYou, e.ask)
            runs[e.session] = r
            return [.notify(e.session, .needsYou)] // even a sub-thread you never prompted blocks your work
        case "Resume", "PostToolUse": // you answered (PostToolUse: hooks connected by an older TaskDock)
            if old?.state == .needsYou {
                runs[e.session]?.state = .working
                runs[e.session]?.ask = nil
            }
            return []
        case "Interrupt": // you stopped it: done and seen, no banner, but the chat stays yours
            guard var r = old, r.state != .finished else { return [] }
            r.finish(at: c.now)
            r.seen = true
            runs[e.session] = r
            return []
        case "SessionEnd":
            runs[e.session] = nil
            return []
        default:
            return []
        }
    }

    /// Every 20 s: forget runs silent for 3 hours; a turn left waiting on background work for 30 minutes
    /// (a dev server never ends) counts as finished. Delegates have no cap: each reports back, even when cancelled.
    static func expire(_ runs: inout [String: Run], now: Date) -> [Effect] {
        var effects: [Effect] = []
        for (id, r) in runs {
            if now.timeIntervalSince(r.last ?? r.since) > 3 * 3600 {
                runs[id] = nil
            } else if r.state == .working, r.delegatesSince == nil, let w = r.waitingSince, now.timeIntervalSince(w) > 30 * 60 {
                runs[id]?.finish(at: now)
                if r.yours { effects.append(.notify(id, .finished)) }
            }
        }
        return effects
    }

    /// "HANDOFF.md" from T3's "[HANDOFF.md](HANDOFF.md)"; else the project folder's name.
    static func label(_ title: String?, cwd: String?) -> String? {
        if let t = title?.replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
            return String(t.prefix(48))
        }
        return cwd.map { URL(fileURLWithPath: $0).lastPathComponent }
    }

    /// Reads new, complete transcript lines: counts delegates in and out, and reports whether the last
    /// message is your interrupt (an interrupt sends no hook event), when the newest message was written, and
    /// the calls (`Agent.call`) whose results came: one a request asked about means you answered it.
    /// A delegate is out from its call until its "Delegated task node" report; one that failed to start, or a
    /// `mode: wait` one that answered in place, never was. A wait that timed out stays out until its report.
    typealias Reading = (interrupted: Bool, latest: Date?, results: [String])
    static func read(_ text: String, _ d: inout Delegates) -> Reading {
        var interrupted = false, latest: Date?, results: [String] = []
        for line in text.split(separator: "\n") where line.contains(#""type":"user""#) || line.contains(#""type":"assistant""#) {
            guard let j = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let type = j["type"] as? String, type == "user" || type == "assistant" else { continue }
            if let ts = (j["timestamp"] as? String).flatMap(isoDate) { latest = max(latest ?? ts, ts) }
            let content = (j["message"] as? [String: Any])?["content"]
            let blocks = content as? [[String: Any]] ?? []
            // Only Claude Code's own marker: a text block that is the marker, not a file or tool output quoting it.
            interrupted = type == "user" && blocks.contains { $0["type"] as? String == "text"
                && ($0["text"] as? String)?.hasPrefix("[Request interrupted by user") == true }
            if type == "assistant" {
                for b in blocks where b["type"] as? String == "tool_use" {
                    guard let id = b["id"] as? String, let name = b["name"] as? String else { continue }
                    if d.tools == nil { d.tools = [:] }
                    d.tools?[id] = call(name, b["input"])
                    guard name.hasSuffix("delegate_task") else { continue }
                    d.calls[id] = (b["input"] as? [String: Any])?["mode"] as? String == "wait"
                    d.open += 1
                }
                continue
            }
            let report = "Delegated task node"
            if (content as? String)?.hasPrefix(report) == true || blocks.contains(where: { ($0["text"] as? String)?.hasPrefix(report) == true }) {
                d.open = max(0, d.open - 1)
            }
            for b in blocks where b["type"] as? String == "tool_result" {
                guard let id = b["tool_use_id"] as? String else { continue }
                if let call = d.tools?.removeValue(forKey: id) { results.append(call) }
                guard let wait = d.calls.removeValue(forKey: id) else { continue }
                let timedOut = "\(b["content"] ?? "")".contains("waitTimedOut")
                if b["is_error"] as? Bool == true || (wait && !timedOut) { d.open = max(0, d.open - 1) }
            }
        }
        return (interrupted, latest, results)
    }

    /// Who wrote a prompt, from its transcript line (found by Claude Code's prompt id): true when you typed it in
    /// a terminal, false when something else did (a wake-up, a script). Nil when it can't tell: not written yet,
    /// an older Claude Code, or another host (T3 and the SDK record every prompt the same way).
    static func typed(_ text: String, prompt: String) -> Bool? {
        for line in text.split(separator: "\n") where line.contains(prompt) {
            guard let j = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  j["type"] as? String == "user", j["promptId"] as? String == prompt else { continue }
            guard j["entrypoint"] as? String == "cli" else { return nil }
            if let origin = j["origin"] as? [String: Any] { return origin["kind"] as? String == "human" } // else a meta line: look on
        }
        return nil
    }

    /// A tool call's fingerprint: its name and a hash of its input. The hook passes this, never the input itself.
    static func call(_ name: String, _ input: Any?) -> String {
        let data = input.flatMap { try? JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys, .fragmentsAllowed]) } ?? Data()
        return name + ":" + SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    private static func isoDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }

    // MARK: Hook mode

    /// Reads the hook's JSON from stdin, posts it to the running app, and exits. Prints nothing:
    /// Claude Code adds a UserPromptSubmit hook's output to the conversation.
    static func hook() -> Never {
        if let e = event(FileHandle.standardInput.readDataToEndOfFile()) {
            DistributedNotificationCenter.default().postNotificationName(note, object: nil, userInfo: e, deliverImmediately: true)
        }
        exit(0)
    }

    /// The fields TaskDock uses from a hook's input (no prompt text).
    static func event(_ data: Data) -> [String: String]? {
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = j["hook_event_name"] as? String, let id = j["session_id"] as? String else { return nil }
        var e = ["event": name, "session": id]
        e["title"] = j["session_title"] as? String
        e["cwd"] = j["cwd"] as? String
        e["transcript"] = j["transcript_path"] as? String
        if let b = j["background_tasks"] as? [Any], !b.isEmpty { e["background"] = "1" }
        if name == "UserPromptSubmit" { e["promptId"] = j["prompt_id"] as? String }
        if name == "PermissionRequest", let tool = j["tool_name"] as? String { e["ask"] = call(tool, j["tool_input"]) }
        // Only this flag leaves the hook, never the prompt text. Wake-ups seen in T3 start like this.
        if let p = j["prompt"] as? String, ["<task-notification>", "Delegated task node"].contains(where: p.hasPrefix) {
            e["automatic"] = "1"
        }
        e["host"] = hostApp()
        return e
    }

    /// The app this hook runs under (hook → claude → T3 Code / Terminal), by walking up parent processes.
    static func hostApp() -> String? {
        var pid = getppid()
        for _ in 0..<12 where pid > 1 {
            if let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular, let id = app.bundleIdentifier {
                return id
            }
            var info = kinfo_proc(), size = MemoryLayout<kinfo_proc>.size
            var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
            guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
            pid = info.kp_eproc.e_ppid
        }
        return nil
    }

    // MARK: Claude Code settings

    /// Event → tool matcher. Answering a request is seen in the transcript, so no PostToolUse hook.
    static let hooks: [(event: String, matcher: String?)] = [
        ("UserPromptSubmit", nil), ("Stop", nil), ("PermissionRequest", nil), ("SessionEnd", nil),
    ]
    private static let marker = "_taskdock"
    /// Dev runs on sample data (TASKDOCK_DATA_DIR) never touch your real Claude Code settings.
    static let settingsFile = ProcessInfo.processInfo.environment["TASKDOCK_DATA_DIR"]
        .map { URL(fileURLWithPath: $0).appendingPathComponent("claude-settings.json") }
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")

    /// The hook command: this binary in hook mode. Never fails, so Claude Code is never blocked.
    static var command: String {
        let path = (Bundle.main.executablePath ?? "").replacingOccurrences(of: "'", with: "'\\''")
        return "'\(path)' agent 2>/dev/null || true"
    }

    /// Any TaskDock hook present (an older version may have installed fewer).
    static func isConnected(_ settings: [String: Any]) -> Bool {
        (settings["hooks"] as? [String: Any] ?? [:]).values.contains { ($0 as? [[String: Any]] ?? []).contains { $0[marker] != nil } }
    }

    /// Exactly TaskDock's current hooks are installed and run this command (other hooks and their order
    /// don't matter). An older version's extra hook (PostToolUse) makes it not current, so launch repairs it.
    static func isCurrent(_ settings: [String: Any], command: String) -> Bool {
        let all = settings["hooks"] as? [String: Any] ?? [:]
        let ours = all.values.reduce(0) { $0 + ($1 as? [[String: Any]] ?? []).filter { $0[marker] != nil }.count }
        return ours == hooks.count && hooks.allSatisfy { h in
            (all[h.event] as? [[String: Any]] ?? []).contains { e in
                e[marker] != nil && e["matcher"] as? String == h.matcher
                    && (e["hooks"] as? [[String: Any]])?.first?["command"] as? String == command
            }
        }
    }

    /// Settings with TaskDock's hooks added (or replaced), keeping every other hook.
    static func connect(_ settings: [String: Any], command: String) -> [String: Any] {
        var s = disconnect(settings), all = s["hooks"] as? [String: Any] ?? [:]
        for h in hooks {
            var entry: [String: Any] = ["hooks": [["type": "command", "command": command, "timeout": 5]], marker: true]
            entry["matcher"] = h.matcher
            all[h.event] = (all[h.event] as? [[String: Any]] ?? []) + [entry]
        }
        s["hooks"] = all
        return s
    }

    /// Settings with only TaskDock's hooks removed.
    static func disconnect(_ settings: [String: Any]) -> [String: Any] {
        var s = settings
        guard var all = s["hooks"] as? [String: Any] else { return s }
        for (e, v) in all {
            guard let list = v as? [[String: Any]] else { continue }
            let kept = list.filter { $0[marker] == nil }
            all[e] = kept.isEmpty ? nil : kept
        }
        s["hooks"] = all.isEmpty ? nil : all
        return s
    }

    static func readSettings() -> [String: Any]? {
        guard let data = try? Data(contentsOf: settingsFile) else { return [:] } // no file yet
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any] // nil: unreadable, leave it alone
    }

    /// Writes the settings. The first write keeps a backup of the original next to them.
    static func writeSettings(_ s: [String: Any]) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: settingsFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        let backup = settingsFile.appendingPathExtension("taskdock-backup")
        if fm.fileExists(atPath: settingsFile.path), !fm.fileExists(atPath: backup.path) {
            try fm.copyItem(at: settingsFile, to: backup)
        }
        let data = try JSONSerialization.data(withJSONObject: s, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: settingsFile, options: .atomic)
    }

    // MARK: System

    /// Nil when running outside an app bundle (`swift run`, the e2e test), where the center would crash.
    static var center: UNUserNotificationCenter? { Bundle.main.bundleIdentifier == nil ? nil : .current() }

    /// Asks once; macOS remembers the answer. Logs what was decided, since a silent "no" looks like a bug.
    static func requestPermission() {
        center?.requestAuthorization(options: [.alert, .sound]) { granted, error in
            NSLog("TaskDock: notifications \(granted ? "allowed" : "not allowed")\(error.map { " (\($0.localizedDescription))" } ?? "")")
            DispatchQueue.main.async { MainActor.assumeIsolated { Agents.shared.notificationsAllowed = granted } }
        }
    }

    #if DEBUG
    /// The e2e test sets these instead of real input, the frontmost app and banners.
    static var testInputAge: TimeInterval?
    static var testFrontmost: String?
    static var sent: [String] = []
    #endif

    static var frontmost: String? {
        #if DEBUG
        if let t = testFrontmost { return t }
        #endif
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    /// Seconds since the last key press. Clicks don't count: clicking around in T3 while waiting isn't sending.
    static var inputAge: TimeInterval {
        #if DEBUG
        if let t = testInputAge { return t }
        #endif
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
    }

    /// A banner: the chat's name, where it runs (task or app), and what happened. Grouped per task.
    /// A finished banner's text: "Done in under a minute", "Done after 23 min", "Done after 1 h 5 min".
    static func done(after t: TimeInterval) -> String {
        let m = Int(t / 60)
        return m < 1 ? "Done in under a minute"
            : "Done after " + (m < 60 ? "\(m) min" : m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(m % 60) min")
    }

    static func notify(id: String, title: String, subtitle: String, body: String, group: String, sound: Bool) {
        #if DEBUG
        sent.append("\(title)|\(subtitle)|\(body)")
        #endif
        let c = UNMutableNotificationContent()
        c.title = title
        c.subtitle = subtitle
        c.body = body
        c.threadIdentifier = group
        c.userInfo = ["session": id]
        if sound { c.sound = .default }
        // One per chat: a newer state replaces its older banner.
        center?.add(UNNotificationRequest(identifier: id, content: c, trigger: nil)) { error in
            if let error { NSLog("TaskDock: notification not shown: \(error.localizedDescription)") }
        }
    }
}

/// The live runs: applies hook events, nudges, notifies, and remembers runs across restarts.
@MainActor
final class Agents: ObservableObject {
    static let shared = Agents()

    /// Off when you declined (or missed) macOS's prompt; the menu then offers to turn them on.
    @Published var notificationsAllowed = true
    @Published private(set) var runs: [String: Agent.Run] = [:] {
        didSet { save() }
    }

    /// A run still going this long after your prompt is a long wait: offer another task.
    static let nudgeAfter: TimeInterval = {
        #if DEBUG
        if let s = ProcessInfo.processInfo.environment["TASKDOCK_NUDGE_AFTER"].flatMap(TimeInterval.init) { return s }
        #endif
        return 120
    }()

    private var file: URL { Store.dir.appendingPathComponent("agents.json") }

    func boot() {
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode([String: Agent.Run].self, from: data) {
            runs = saved
        }
        DistributedNotificationCenter.default().addObserver(forName: Agent.note, object: nil, queue: .main) { n in
            guard let e = Agent.Event(n.userInfo) else { return }
            MainActor.assumeIsolated { Agents.shared.handle(e) }
        }
        // What sends no hook event (an interrupt, your answer) is read from the transcripts this often.
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in MainActor.assumeIsolated { Agents.shared.scan(Date()) } }
    }

    private func save() {
        try? JSONEncoder().encode(runs).write(to: file, options: .atomic)
    }

    /// A hook event. A chat T3 Code knows belongs to `T3`, whose records are exact: its hook events would count it twice.
    func handle(_ e: Agent.Event) {
        // A prompt waits a moment: T3 may not have recorded a new chat yet (3 s), and Claude Code writes who wrote it
        // to the transcript just after the hook (1 s). Any other event of the chat lets it through first.
        flush(e.session)
        let wait: Double? = e.name != "UserPromptSubmit" ? nil
            : T3.shared.available && e.host == T3.app ? 3 : e.prompt != nil && e.transcript != nil ? 1 : nil
        if let wait {
            let token = UUID()
            pending[e.session] = (e, context(), size(e.transcript), token)
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) { self.flush(e.session, token) }
            return
        }
        apply(e, context(), from: size(e.transcript))
    }

    /// Prompts waiting to be applied: the event, what was around when it came, the transcript's size then, and
    /// which prompt it is (a later one in the same chat has its own timer).
    private var pending: [String: (event: Agent.Event, context: Agent.Context, from: UInt64, token: UUID)] = [:]

    private func flush(_ session: String, _ token: UUID? = nil) {
        guard let p = pending[session], token == nil || token == p.token else { return }
        // A new T3 chat's prompt waits for T3 even when another of its events comes first (that one is dropped, as a
        // hook event for a chat no one tracks yet), so it can't be tracked twice.
        if token == nil, p.event.host == T3.app, T3.shared.available { return }
        pending[session] = nil
        var e = p.event
        // From a little before the size seen: the line may be written before the event reaches the app. The id is unique.
        if let id = e.prompt, let path = e.transcript, let (data, _) = tail(path, from: p.from > 65536 ? p.from - 65536 : 0) {
            e.sent = Agent.typed(String(decoding: data, as: UTF8.self), prompt: id)
        }
        apply(e, p.context, from: p.from)
    }

    /// What a file gained after `from` (nothing if it's shorter now), and its size; nil when it can't be read.
    private func tail(_ path: String, from: UInt64) -> (data: Data, end: UInt64)? {
        guard let h = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? h.close() }
        let end = (try? h.seekToEnd()) ?? 0
        guard from <= end else { return (Data(), end) }
        try? h.seek(toOffset: from)
        return ((try? h.readToEnd()) ?? Data(), end)
    }

    private func size(_ path: String?) -> UInt64 {
        path.flatMap { try? FileManager.default.attributesOfItem(atPath: $0)[.size] as? UInt64 } ?? 0
    }

    /// `from`: the transcript's size when the event came; a new run reads it from there on.
    private func apply(_ e: Agent.Event, _ c: Agent.Context, from: UInt64) {
        var e = e
        if T3.shared.available, let thread = T3.shared.thread(forSession: e.session) {
            // Tracked by its hooks before (an older version, or while T3 couldn't be read): T3 has it now.
            if let old = runs[e.session] {
                var r = runs
                r[e.session] = nil
                if old.yours, var t = r[thread] {
                    t.yours = true
                    if t.template == nil { (t.template, t.goal) = (old.template, old.goal) }
                    r[thread] = t
                }
                runs = r
            }
            return
        }
        var r = runs
        // A turn that started delegates isn't done until every one has reported back.
        if e.name == "Stop", r[e.session] != nil {
            _ = scan(e.session, in: &r)
            e.delegates = (r[e.session]?.delegates?.open ?? 0) > 0
        }
        let effects = Agent.apply(e, to: &r, c)
        if e.name == "UserPromptSubmit", r[e.session]?.read == nil { r[e.session]?.read = from }
        runs = r
        perform(effects)
    }

    /// Events from T3 Code's own records.
    func receive(_ events: [Agent.Event]) {
        var r = runs, effects: [Agent.Effect] = []
        let c = context()
        for e in events { effects += Agent.apply(e, to: &r, c) }
        if r != runs { runs = r }
        perform(effects)
    }

    private func context(_ now: Date = Date()) -> Agent.Context {
        let s = Store.shared.session
        return .init(now: now, task: s?.template.id, goal: s?.goal ?? "", inputAge: Agent.inputAge, frontmost: Agent.frontmost)
    }

    private func perform(_ effects: [Agent.Effect]) {
        for effect in effects {
            switch effect {
            case let .nudgeLater(id, since):
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.nudgeAfter) { self.nudge(id, since) }
            case let .notify(id, state):
                guard let run = runs[id] else { continue }
                Agent.notify(id: id, title: run.title, subtitle: place(run),
                             body: state == .needsYou ? "Waiting for your answer" : Agent.done(after: run.took ?? 0),
                             group: run.template?.uuidString ?? run.host ?? "agents", sound: state == .needsYou)
            }
        }
    }

    /// Every 20 s: expire old runs; mark finished runs you've looked at as seen (a T3 chat: it's open in T3 with
    /// T3 in front; another chat: its app is in front, in its task or with no task running).
    func tick(_ now: Date) {
        var r = runs
        for id in T3.shared.chats.keys where r[id] != nil { r[id]?.last = now } // still in T3's list: not silent
        let effects = Agent.expire(&r, now: now)
        let front = Agent.frontmost, task = Store.shared.session?.template.id, t3 = T3.shared
        for (id, run) in r where run.state == .finished && !run.seen {
            let looked = if t3.chats[id] != nil {
                front == T3.app && t3.onScreen == id // that chat open in T3, in front
            } else {
                run.host != nil && run.host == front && run.template == task
            }
            if looked {
                r[id]?.seen = true
                Agent.center?.removeDeliveredNotifications(withIdentifiers: [id])
            }
        }
        if r != runs { runs = r }
        perform(effects)
    }

    /// Every 2 s, hook runs: reads their transcripts for what sends no event, an interrupt or your answer. Answered
    /// means the call it asked about got its result (allowed or denied). When that call isn't among the open ones (a
    /// sub-agent's call lives in its own transcript; or its input reached the hook changed), or there's no call to go
    /// by (an older hook): any message after the request.
    func scan(_ now: Date) {
        var r = runs, effects: [Agent.Effect] = []
        for (id, run) in r where run.state != .finished && T3.shared.chats[id] == nil {
            guard let (interrupted, latest, results) = scan(id, in: &r) else { continue }
            var answered = false
            if run.state == .needsYou {
                let known = run.ask.map { a in r[id]?.delegates?.tools?.values.contains(a) == true || results.contains(a) } ?? false
                answered = known ? run.ask.map(results.contains) == true : (latest ?? .distantPast) > (run.last ?? run.since)
            }
            if interrupted || answered { effects += Agent.apply(.init(name: interrupted ? "Interrupt" : "Resume", session: id), to: &r, context(now)) }
        }
        if r != runs { runs = r }
        perform(effects)
    }

    /// Reads the complete lines a hook run's transcript gained since last time; nil when there's nothing to read.
    private func scan(_ id: String, in r: inout [String: Agent.Run]) -> Agent.Reading? {
        guard let run = r[id], let path = run.transcript, let (data, end) = tail(path, from: run.read ?? .max) else { return nil }
        guard let from = run.read, from <= end else { r[id]?.read = end; return nil } // saved by an older version, or replaced
        guard let cut = data.lastIndex(of: 10) else { return nil }
        var d = run.delegates ?? .init()
        let result = Agent.read(String(decoding: data[..<cut], as: UTF8.self), &d)
        r[id]?.delegates = d
        r[id]?.read = from + UInt64(cut - data.startIndex + 1)
        return result
    }

    /// Your prompt is still running and you're still in its task: offer another task. Waits while you
    /// type (a nudge must never catch keystrokes) or while the picker is open.
    private func nudge(_ id: String, _ since: Date) {
        guard let r = runs[id], r.since == since, r.state == .working, !r.nudged,
              Store.shared.session?.template.id == r.template else { return }
        if Agent.inputAge < 10 || Windows.picker?.isVisible == true {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self.nudge(id, since) }
            return
        }
        // One picker covers every run of this task that's waiting, so a burst of prompts nudges once.
        for (k, v) in runs where v.template == r.template && v.state == .working && v.yours { runs[k]?.nudged = true }
        Windows.togglePicker(switching: Store.shared.session != nil, nudge: r.template ?? Agents.noTask)
    }

    /// A nudge you clicked away from: the menu offers it again, quietly, while that task's agent still works.
    @Published var later: UUID?
    var laterStillWorking: UUID? {
        later.flatMap { n in runs.values.contains { $0.template == (n == Self.noTask ? nil : n) && $0.state == .working && $0.yours } ? n : nil }
    }

    /// Stands in for "no task" in the picker's nudge.
    static let noTask = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    // MARK: Tasks

    /// Runs of a task that still work or wait on you: the task is parked, its apps never quit.
    func busy(_ template: UUID) -> Bool { runs.values.contains { $0.template == template && $0.state != .finished } }

    /// Apps hosting a run that isn't finished; never quit.
    var hosts: Set<String> { Set(runs.values.filter { $0.state != .finished }.compactMap(\.host)) }

    /// You came back to (or finished) this task: its finished runs are seen.
    func seen(_ template: UUID) {
        for (id, run) in runs where run.template == template && run.state == .finished && !run.seen { markSeen(id) }
    }

    private func markSeen(_ id: String) {
        runs[id]?.seen = true
        Agent.center?.removeDeliveredNotifications(withIdentifiers: [id])
    }

    /// Back to the run's task (if it had one) and its chat's app.
    func open(_ id: String) {
        guard let run = runs[id] else { return }
        let store = Store.shared
        if let t = run.template, store.session?.template.id != t, let template = store.templates.first(where: { $0.id == t }) {
            store.start(template, goal: run.goal.isEmpty ? template.name : run.goal, show: run.host)
        }
        if run.state == .finished { markSeen(id) }
        if let host = run.host {
            Snapshot.running(host).first.map { $0.unhide(); $0.activate() }
        }
    }

    /// "💻 Coding" or, without a task, the agent's app name.
    func place(_ run: Agent.Run) -> String {
        if let t = Store.shared.templates.first(where: { $0.id == run.template }) { return "\(t.emoji) \(t.name)" }
        // "T3 Code (Beta)" reads as "T3 Code".
        let app = run.host.flatMap { Snapshot.running($0).first?.localizedName }?
            .replacingOccurrences(of: #"\s*\(.*\)$"#, with: "", options: .regularExpression)
        return app ?? "Claude Code"
    }

    func note(_ run: Agent.Run, now: Date) -> String {
        switch run.state {
        case .working: "working · \(elapsedText(since: run.since, now: now))"
        case .finished: "finished \(elapsedText(since: run.since, now: now)) ago"
        case .needsYou: "needs you"
        }
    }

    /// "2 agents working", "Agent finished 3m ago", "Agent needs you"… for a task's picker row.
    func note(for template: UUID, now: Date) -> String? {
        let mine = shown.values.filter { $0.template == template }
        guard let top = mine.max(by: { Self.rank($0) < Self.rank($1) }) else { return nil }
        let same = mine.filter { $0.state == top.state }.count
        return same > 1 ? "\(same) agents \(top.state == .working ? "working" : top.state == .finished ? "finished" : "need you")"
            : "Agent \(note(top, now: now))"
    }

    /// Every state among the runs you'd care about, most urgent first, for the menu bar ("! ⧗ ✓").
    var badge: [Agent.State] {
        let states = Set(shown.map(\.value.state))
        return [Agent.State.needsYou, .working, .finished].filter(states.contains)
    }

    /// Your runs, plus any run that needs you (a sub-thread's question blocks your work too).
    private var shown: [String: Agent.Run] { runs.filter { ($0.value.yours && !$0.value.seen) || $0.value.state == .needsYou } }

    /// One menu row per chat: most urgent first, then newest.
    var list: [(id: String, run: Agent.Run)] {
        shown.map { ($0.key, $0.value) }.sorted { (Self.rank($0.run), $0.run.since) > (Self.rank($1.run), $1.run.since) }
    }

    private static func rank(_ r: Agent.Run) -> Int { r.state == .needsYou ? 2 : r.state == .finished ? 1 : 0 }
}
