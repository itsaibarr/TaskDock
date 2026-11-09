import Foundation
import SQLite3

/// T3 Code's own record of its chats, read from its database, read-only (`docs/specs/agent-handoff.md`,
/// "Reading T3 Code directly"). Every query lives here. Exact for every provider (Claude, Codex…): who sent each
/// prompt, delegates, background work, questions and approvals, interrupts. If anything is off (no file, a schema
/// change, an error) it goes quiet and the Claude Code hooks work as before.
@MainActor
final class T3 {
    static let shared = T3()
    nonisolated static let app = "com.t3tools.t3code"

    /// One chat's latest run, as T3 records it. Only ids, states, times and the title; never message text.
    struct Chat: Equatable {
        var run: String
        var status: String
        /// You wrote the prompt that started the run in T3's window (Send button, dictation or ↩ alike); not a
        /// wake-up, a delegate, or T3 resuming a chat by itself (`creationSource: server`).
        var sent: Bool
        var title: String
        var needsYou: Bool
        /// Delegates it started that haven't delivered their report yet.
        var delegates: Bool
        /// Background work T3 holds the chat open for (work the agent waits on, a background agent): no time cap.
        var holds = false
        /// Other background work still running (a command, a monitor; a dev server may never end).
        var background = false

        enum Phase { case working, delegating, waiting, finished, interrupted }
        /// A delegate reports back even after an interrupt; background work left running doesn't keep an interrupted chat.
        var phase: Phase {
            ["queued", "preparing", "starting", "running", "waiting"].contains(status) ? .working
                : delegates ? .delegating : ["interrupted", "cancelled"].contains(status) ? .interrupted
                : holds ? .delegating : background ? .waiting : .finished
        }
    }

    private(set) var available = false
    /// Chats with a run in the last 3 hours, by T3 thread id (the run's key in `Agents`).
    private(set) var chats: [String: Chat] = [:]
    /// The chat open in T3's window (T3 marks it visited every few seconds while it's open).
    private(set) var onScreen: String?
    private var reader: Reader?
    private var first = true

    func boot() {
        poll()
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in MainActor.assumeIsolated { T3.shared.poll() } }
    }

    func poll() {
        let now = Date()
        // Opt-in, with the hooks: "Connect Claude Code…" turns both on, Disconnect both off.
        if Store.shared.claudeConnected { reader = reader ?? Reader(path: Reader.file) } else { reader = nil }
        guard let r = reader, let new = r.chats(now: now), let screen = r.onScreen(now: now) else {
            if available { NSLog("TaskDock: can't read T3 Code; using Claude Code hooks only") }
            (reader, available, first, chats, onScreen) = (nil, false, true, [:], nil)
            return
        }
        if !available { NSLog("TaskDock: reading T3 Code") }
        available = true
        let events = Self.events(from: first ? nil : chats, to: new)
        (first, chats, onScreen) = (false, new, screen)
        if !events.isEmpty { Agents.shared.receive(events) }
    }

    /// The T3 chat a Claude Code session belongs to, if T3 runs it.
    func thread(forSession id: String) -> String? { reader?.thread(forSession: id) }

    /// What changed since the last read, as events for `Agent.apply`. `old` is nil on the first read after
    /// launch: chats already working are tracked (their app protected) but not taken as just sent.
    nonisolated static func events(from old: [String: Chat]?, to new: [String: Chat]) -> [Agent.Event] {
        var events: [Agent.Event] = []
        for (id, n) in new.sorted(by: { $0.key < $1.key }) {
            func event(_ name: String) -> Agent.Event { .init(name: name, session: id, title: n.title, host: app) }
            let o = old?[id], same = o?.run == n.run
            if !same && (old != nil || ![.finished, .interrupted].contains(n.phase)) {
                var e = event("UserPromptSubmit")
                e.sent = old != nil && n.sent
                e.automatic = e.sent == false
                events.append(e)
            }
            let wasNeeds = same && o?.needsYou == true
            if n.needsYou != wasNeeds { events.append(event(n.needsYou ? "PermissionRequest" : "Resume")) }
            if n.phase != (same ? o!.phase : .working) {
                var e = event(n.phase == .interrupted ? "Interrupt" : "Stop")
                e.delegates = n.phase == .delegating
                e.background = n.phase == .waiting
                if n.phase != .working { events.append(e) }
            }
        }
        // A chat gone from T3's list (deleted, or quiet for 3 hours) is forgotten, not left working.
        for id in (old ?? [:]).keys.sorted() where new[id] == nil { events.append(.init(name: "SessionEnd", session: id)) }
        return events
    }

    /// The database queries. Read-only; any failure returns nil.
    struct Reader {
        /// Dev runs on sample data (TASKDOCK_DATA_DIR) read a test copy there, never your real T3.
        static let file = ProcessInfo.processInfo.environment["TASKDOCK_DATA_DIR"].map { $0 + "/t3.sqlite" }
            ?? NSHomeDirectory() + "/.t3/userdata/statev2.sqlite"
        /// The schema these queries were checked against (T3 server 0.1.7). Newer is fine while they still run.
        static let migration = 79

        private final class Handle {
            let db: OpaquePointer
            init(_ db: OpaquePointer) { self.db = db }
            deinit { sqlite3_close(db) }
        }
        private let handle: Handle

        init?(path: String) {
            var db: OpaquePointer?
            guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else { sqlite3_close(db); return nil }
            handle = Handle(db)
            sqlite3_busy_timeout(db, 200)
            guard let v = rows("SELECT max(migration_id) FROM effect_sql_migrations")?.first?[0].flatMap(Int.init), v >= Self.migration else { return nil }
        }

        func chats(now: Date) -> [String: Chat]? {
            // Background work (T3's `pendingBackgroundTasks`, every provider that reports it) holds a chat open by T3's own
            // rule: when the agent waits on it, or it's a background agent or task; not a plain command. Unlike T3, only on
            // the provider thread that ran the latest run, so work left on an earlier one (a provider switch) can't pin it.
            // One value: NULL none, 0 some (all plain), 1 some it holds the chat open for.
            let tasks = """
                (SELECT max(json_extract(j.value, '$.awaited') IS 1 OR (json_extract(j.value, '$.kind') IN ('subagent', 'background_task')) IS 1)
                 FROM orchestration_v2_projection_provider_threads p, json_each(p.payload_json, '$.pendingBackgroundTasks') j
                 WHERE p.thread_id = r.thread_id AND coalesce(p.last_run_ordinal, r.ordinal) = r.ordinal)
                """
            let sql = """
                SELECT r.thread_id, r.run_id, r.status,
                  json_extract(m.payload_json, '$.createdBy') = 'user' AND json_extract(m.payload_json, '$.creationSource') = 'web',
                  t.title,
                  EXISTS (SELECT 1 FROM orchestration_v2_projection_runtime_requests q
                          WHERE q.thread_id = r.thread_id AND q.status = 'pending' AND q.created_at > ?1),
                  EXISTS (SELECT 1 FROM orchestration_v2_projection_subagents s
                          WHERE s.thread_id = r.thread_id AND s.origin = 'app_owned' AND s.updated_at > ?2
                            AND coalesce(s.completion_delivery_state, '') NOT IN ('delivered', 'acknowledged', 'disposed')),
                  \(tasks)
                FROM orchestration_v2_projection_runs r
                JOIN orchestration_v2_projection_threads t ON t.thread_id = r.thread_id
                LEFT JOIN orchestration_v2_projection_messages m ON m.message_id = json_extract(r.payload_json, '$.userMessageId')
                WHERE t.deleted_at IS NULL
                  AND r.ordinal = (SELECT max(ordinal) FROM orchestration_v2_projection_runs WHERE thread_id = r.thread_id)
                  -- started or ended in 3 h, or still working (a long run, delegates out) up to a day so a stuck row can't pin it
                  AND (coalesce(r.completed_at, r.requested_at) > ?1 OR (r.requested_at > ?2 AND (r.status IN ('queued', 'preparing', 'starting', 'running', 'waiting')
                       OR EXISTS (SELECT 1 FROM orchestration_v2_projection_subagents s WHERE s.thread_id = r.thread_id
                                  AND s.origin = 'app_owned' AND s.updated_at > ?2 AND coalesce(s.completion_delivery_state, '') NOT IN ('delivered', 'acknowledged', 'disposed'))
                       OR \(tasks) = 1)))
                """
            guard let rows = rows(sql, [Self.stamp(now.addingTimeInterval(-3 * 3600)), Self.stamp(now.addingTimeInterval(-24 * 3600))])
            else { return nil }
            var chats: [String: Chat] = [:]
            for c in rows {
                guard let id = c[0], let run = c[1], let status = c[2] else { continue }
                chats[id] = Chat(run: run, status: status, sent: c[3] == "1", title: c[4] ?? "T3 Code", needsYou: c[5] == "1",
                                 delegates: c[6] == "1", holds: c[7] == "1", background: c[7] != nil)
            }
            return chats
        }

        /// The chat opened last (".some(nil)": none in the last 3 hours); nil when the query fails. Filtered on the
        /// visit itself: opening a chat doesn't always touch its `updated_at`.
        func onScreen(now: Date) -> String?? {
            let sql = """
                SELECT thread_id FROM orchestration_v2_projection_threads
                WHERE json_extract(payload_json, '$.lastVisitedAt') > ?1 AND deleted_at IS NULL
                ORDER BY json_extract(payload_json, '$.lastVisitedAt') DESC LIMIT 1
                """
            return rows(sql, [Self.stamp(now.addingTimeInterval(-3 * 3600))]).map { $0.first?[0] ?? nil }
        }

        func thread(forSession id: String) -> String? {
            let sql = """
                SELECT thread_id FROM orchestration_v2_projection_provider_threads
                WHERE json_extract(payload_json, '$.nativeThreadRef.nativeId') = ?1 LIMIT 1
                """
            return rows(sql, [id])?.first?[0] ?? nil
        }

        private func rows(_ sql: String, _ args: [String] = []) -> [[String?]]? {
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(handle.db, sql, -1, &st, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(st) }
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            for (i, a) in args.enumerated() { sqlite3_bind_text(st, Int32(i + 1), a, -1, transient) }
            var out: [[String?]] = []
            while true {
                switch sqlite3_step(st) {
                case SQLITE_ROW:
                    out.append((0..<sqlite3_column_count(st)).map { sqlite3_column_text(st, $0).map { String(cString: $0) } })
                case SQLITE_DONE: return out
                default: return nil
                }
            }
        }

        private static func stamp(_ d: Date) -> String {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f.string(from: d)
        }

        #if DEBUG
        /// The tables and columns the queries use, for test fixtures.
        static let schema = """
            CREATE TABLE "effect_sql_migrations" (migration_id integer PRIMARY KEY NOT NULL,
              created_at datetime NOT NULL DEFAULT current_timestamp, name VARCHAR(255) NOT NULL);
            CREATE TABLE orchestration_v2_projection_threads (thread_id TEXT PRIMARY KEY, title TEXT NOT NULL,
              updated_at TEXT NOT NULL, deleted_at TEXT, payload_json TEXT NOT NULL);
            CREATE TABLE orchestration_v2_projection_runs (run_id TEXT PRIMARY KEY, thread_id TEXT NOT NULL, ordinal INTEGER NOT NULL,
              provider TEXT NOT NULL, status TEXT NOT NULL, requested_at TEXT NOT NULL, completed_at TEXT, payload_json TEXT NOT NULL);
            CREATE TABLE orchestration_v2_projection_messages (message_id TEXT PRIMARY KEY, thread_id TEXT NOT NULL, payload_json TEXT NOT NULL);
            CREATE TABLE orchestration_v2_projection_runtime_requests (runtime_request_id TEXT PRIMARY KEY, thread_id TEXT NOT NULL,
              kind TEXT NOT NULL, status TEXT NOT NULL, created_at TEXT NOT NULL, payload_json TEXT NOT NULL);
            CREATE TABLE orchestration_v2_projection_subagents (subagent_id TEXT PRIMARY KEY, thread_id TEXT NOT NULL,
              child_thread_id TEXT, origin TEXT NOT NULL, status TEXT NOT NULL, updated_at TEXT NOT NULL,
              completion_delivery_state TEXT, payload_json TEXT NOT NULL);
            CREATE TABLE orchestration_v2_projection_provider_threads (provider_thread_id TEXT PRIMARY KEY, thread_id TEXT,
              last_run_ordinal INTEGER, payload_json TEXT NOT NULL);
            INSERT INTO effect_sql_migrations VALUES (79, '2026-11-05 03:58:40', 'DelegatedRecoveryIndexes');
            """
        static func now() -> String { stamp(Date()) }
        #endif
    }
}
