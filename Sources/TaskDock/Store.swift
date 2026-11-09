import AppKit

@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    @Published var templates: [Template] = []
    @Published var session: Session?
    @Published var now = Date()
    @Published var browsers = 0
    /// Some connected browser still runs an older extension and needs it reloaded.
    @Published var outdatedExtension = false
    @Published var editorSelection: UUID?
    @Published var claudeConnected = false

    let bridge = Bridge()
    /// Apps a parked task opened (task → bundle IDs): kept running while its agent works, handed back when it
    /// restarts. Saved, so they're still never quit after TaskDock restarts.
    private var parkedApps: [UUID: [String]] = [:] {
        didSet { save(parkedApps, to: Self.dir.appendingPathComponent("parked.json")) }
    }
    /// Sessions that just ended → their template, so a tab report sent right before the end still lands.
    private var ended: [UUID: UUID] = [:]

    static let dir: URL = {
        // TASKDOCK_DATA_DIR points dev runs at sample data instead of your real templates.
        let d = ProcessInfo.processInfo.environment["TASKDOCK_DATA_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("TaskDock", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    private var templatesFile: URL { Self.dir.appendingPathComponent("templates.json") }
    private var sessionFile: URL { Self.dir.appendingPathComponent("session.json") }
    var dockBackupFile: URL { Self.dir.appendingPathComponent("dock-original.plist") }

    func boot() {
        let saved = load([Template].self, from: templatesFile)
        templates = saved ?? []
        // A session that survived a crash or quit is resumed, so Finish can still restore everything.
        session = load(Session.self, from: sessionFile)
        // A deleted task never comes back for its parked apps (unless the templates didn't load: keep them all then).
        parkedApps = (load([UUID: [String]].self, from: Self.dir.appendingPathComponent("parked.json")) ?? [:])
            .filter { p in saved == nil || templates.contains { $0.id == p.key } }
        bridge.stateMessage = { [weak self] in self?.stateMessage ?? [:] }
        bridge.onBrowsersChanged = { [weak self] n, outdated in
            self?.browsers = n
            self?.outdatedExtension = outdated
        }
        // The extension reports the task window's tabs whenever they change, so they're saved before the task ends.
        bridge.onTabs = { [weak self] id, tabs in
            guard let self, let template = session?.id == id ? session?.template.id : ended[id],
                  templates.first(where: { $0.id == template })?.resume?.tabs != tabs else { return }
            updateResume(template) { $0.tabs = tabs }
        }
        bridge.onPost = { Posts.shared.save(from: $0) }
        bridge.savedPostIDs = { Posts.shared.posts.map(\.id) }
        Posts.shared.onIDsChanged = { [weak self] in
            guard let self else { return }
            bridge.broadcast(bridge.savedPostsMessage)
        }
        Posts.shared.boot()
        bridge.start()
        // Only the installed app repairs the hooks; dev builds (`swift run`) would point them at .build.
        if Bundle.main.bundleIdentifier != nil, let s = Agent.readSettings(), Agent.isConnected(s) {
            claudeConnected = true
            Agent.requestPermission()
            // The app moved since connecting: point the hooks at where it is now.
            if !Agent.isCurrent(s, command: Agent.command) { try? Agent.writeSettings(Agent.connect(s, command: Agent.command)) }
        }
        Agents.shared.boot()
        T3.shared.boot()
        Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { _ in
            MainActor.assumeIsolated {
                Store.shared.now = Date()
                Agents.shared.tick(Store.shared.now)
                Posts.shared.tick()
            }
        }
    }

    // MARK: Persistence

    func saveTemplates() { save(templates, to: templatesFile) }

    private func saveSession() {
        if let session { save(session, to: sessionFile) } else { try? FileManager.default.removeItem(at: sessionFile) }
    }

    private func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do { return try JSONDecoder().decode(type, from: data) } catch {
            NSLog("TaskDock: could not read \(url.lastPathComponent): \(error)")
            return nil
        }
    }

    private func save<T: Encodable>(_ value: T, to url: URL) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        do { try enc.encode(value).write(to: url, options: .atomic) } catch {
            NSLog("TaskDock: could not save \(url.lastPathComponent): \(error)")
        }
    }

    // MARK: Templates

    /// Apps open and visible right now (not TaskDock or Finder).
    func currentApps() -> [AppRef] {
        let skip: Set<String> = [Bundle.main.bundleIdentifier ?? "", "com.apple.finder"]
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isHidden && !skip.contains($0.bundleIdentifier ?? "") }
            .compactMap(AppRef.init)
    }

    func captureTemplate() -> Template { Template(name: "New task", apps: currentApps()) }

    func addTemplate(_ t: Template) {
        templates.append(t)
        saveTemplates()
        editorSelection = t.id
    }

    func deleteTemplate(_ id: UUID) {
        // Clear the selection first so the form's index binding never points past the array.
        let i = templates.firstIndex { $0.id == id } ?? 0
        editorSelection = nil
        DispatchQueue.main.async {
            self.templates.removeAll { $0.id == id }
            self.parkedApps[id] = nil
            self.saveTemplates()
            self.editorSelection = self.templates[safe: min(i, self.templates.count - 1)]?.id
        }
    }

    // MARK: Sessions

    var stateMessage: [String: Any] {
        guard let s = session else { return ["type": "state", "session": NSNull()] }
        return ["type": "state", "session": [
            "id": s.id.uuidString,
            "goal": s.goal,
            "name": s.template.name,
            "emoji": s.template.emoji,
            "startedAt": s.startedAt.timeIntervalSince1970 * 1000,
            "browser": s.template.apps.contains(where: \.usesExtension),
            "tabs": s.template.resume?.tabs ?? [],
        ] as [String: Any]]
    }

    /// `resume`: reopen what was open when this task last ended.
    /// `show`: an app to keep in front too (a chat's app when you click its banner).
    func start(_ t: Template, goal: String, resume: Bool = true, show: String? = nil) {
        var t = t
        if !resume { // Start fresh: drop what was saved; this run saves its own state when it ends
            t.resume = nil
            updateTemplate(t.id) { $0.resume = nil }
        }
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        var visible = running.filter { !$0.isHidden }.compactMap(\.bundleIdentifier)
        var dock: Data? // the "home" Dock to return to on finish
        let prev = session
        // A task an agent works for is parked, not closed: its apps (the agent's window) are only hidden.
        let parked = prev.map { Agents.shared.busy($0.template.id) } ?? false

        if let prev {
            // Switching: keep the pre-task home state instead of restoring it in between.
            visible = prev.visibleApps
            dock = prev.dock
            runShortcut(prev.template.endShortcut)
        }
        if t.apps.isEmpty {
            if let home = dock { Dock.restore(home) } // this task uses the normal Dock
            dock = nil
        } else if dock == nil {
            dock = Dock.snapshot()
        }

        // Apps opened for this task are quit when it ends; ones the previous task opened carry over if this task uses them too.
        let ids = Set(t.apps.map(\.bundleID))
        let opened = t.apps.map(\.bundleID).filter { !Snapshot.isRunning($0) } // any kind of app, not just Dock apps
        let inherited = prev?.launched ?? []
        if let prev, parked { parkedApps[prev.template.id] = inherited }
        let returning = parkedApps.removeValue(forKey: t.id) ?? []

        // Save before changing anything, so a crash mid-way can still be undone.
        session = Session(template: t, goal: goal, visibleApps: visible, dock: dock,
                          launched: Array(Set(inherited.filter(ids.contains) + opened + returning)))
        saveSession()

        let keep = ids.union([Bundle.main.bundleIdentifier ?? "", show ?? ""])
        for (i, app) in t.apps.enumerated() {
            if let r = running.first(where: { $0.bundleIdentifier == app.bundleID }) {
                r.unhide()
                if i == 0 { r.activate() }
            } else {
                let cfg = NSWorkspace.OpenConfiguration()
                cfg.activates = i == 0
                NSWorkspace.shared.openApplication(at: app.url, configuration: cfg)
            }
        }
        let hidden = running.filter { !keep.contains($0.bundleIdentifier ?? "") }
        hidden.forEach { $0.hide() }
        // Closing the picker hands focus back to the app that was in front a moment later, which unhides it.
        let id = session?.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if Store.shared.session?.id == id { hidden.forEach { $0.hide() } }
        }

        // Reopen this task's files only after the previous task's open files were read,
        // so an app both tasks use isn't saved with this task's files.
        if let prev {
            saveState(prev) {
                if !parked { Store.shared.quit(inherited) }
                Snapshot.reopen(t.resume?.items ?? [])
            }
        } else {
            Snapshot.reopen(t.resume?.items ?? [])
        }
        restoreWindows(t)
        Agents.shared.seen(t.id) // back in the task: its finished runs are seen

        if let dock { Dock.apply(t.apps, over: dock, backup: dockBackupFile) }
        bridge.broadcast(stateMessage)
        runShortcut(t.startShortcut)
    }

    func finish(note: String) {
        guard let s = session else { return }
        let parked = Agents.shared.busy(s.template.id)
        if parked { parkedApps[s.template.id] = s.launched ?? [] }
        Agents.shared.seen(s.template.id)
        saveState(s) { if !parked { Store.shared.quit(s.launched ?? []) } } // quit only after their open files were read
        session = nil
        saveSession()
        bridge.broadcast(stateMessage)

        if let d = s.dock { Dock.restore(d) }
        let visible = Set(s.visibleApps)
        for app in NSWorkspace.shared.runningApplications where visible.contains(app.bundleIdentifier ?? "") {
            app.unhide()
        }
        runShortcut(s.template.endShortcut)

        let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { updateTemplate(s.template.id) { $0.lastStopNote = note } }
    }

    /// Saves what the task's apps have open onto its template. Browser tabs arrive separately (bridge).
    private func saveState(_ s: Session, then done: @escaping @MainActor () -> Void) {
        ended[s.id] = s.template.id
        // The browser's final report comes right away; a much later one (after a reconnect) must not count.
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { self.ended[s.id] = nil }
        let stamp = Date()
        let apps = s.template.apps, ids = apps.map(\.bundleID)
        // Quick; read now, before the next task moves windows. Extension browsers are left alone:
        // their paused windows share the bundle ID with the task window.
        let spaces = AeroSpace.workspaces(of: apps.filter { !$0.usesExtension }.map(\.bundleID))
        updateResume(s.template.id) { r in
            r.savedAt = stamp
            r.workspaces = (r.workspaces ?? [:]).merging(spaces) { $1 }
        }
        // A plain thread, not a Swift task: the first read of each app waits for the permission prompt.
        DispatchQueue.global().async {
            let (read, unread) = Snapshot.items(apps)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    Store.shared.updateResume(s.template.id) { r in
                        guard r.savedAt == stamp else { return } // a newer save already ran
                        // Running apps report what's open now; earlier files are kept for task apps that were
                        // quit before finishing or couldn't be read.
                        r.items = read + r.items.filter {
                            !read.contains($0) && ids.contains($0.app) && (!Snapshot.isRunning($0.app) || unread.contains($0.app))
                        }
                    }
                    done()
                }
            }
        }
    }

    /// Switches Phi to the task's Space and puts windows back on their AeroSpace workspaces.
    private func restoreWindows(_ t: Template) {
        if t.usesPhi {
            DispatchQueue.global().async { Phi.activate(for: t) }
        }
        let ids = Set(t.apps.filter { !$0.usesExtension }.map(\.bundleID))
        let saved = (t.resume?.workspaces ?? [:]).filter { ids.contains($0.key) }, first = t.apps.first?.bundleID
        DispatchQueue.global().async { AeroSpace.restore(saved, focus: first) }
    }

    /// Asks apps to quit normally, so they can still offer to save unsaved work. Quits only apps nobody else
    /// owns: not the current task's (it may have started while the old task's files were being read), not a
    /// parked task's (two tasks can share an app), not an agent's (T3 Code, Terminal…) while it works.
    private func quit(_ ids: [String]) {
        let inUse = Set(session?.template.apps.map(\.bundleID) ?? [])
        // Restarted right away: the running task now owns them, so they're still quit when it ends.
        let adopted = ids.filter { inUse.contains($0) && session?.launched?.contains($0) == false }
        if !adopted.isEmpty { session?.launched? += adopted; saveSession() }
        let owned = inUse.union(Agents.shared.hosts).union(parkedApps.values.joined())
        for id in ids where id != Bundle.main.bundleIdentifier && !owned.contains(id) {
            Snapshot.running(id).forEach { $0.terminate() }
        }
    }

    // MARK: Agents

    func toggleClaude() {
        guard let s = Agent.readSettings() else {
            return NSLog("TaskDock: ~/.claude/settings.json isn't valid JSON; left it alone")
        }
        do {
            try Agent.writeSettings(claudeConnected ? Agent.disconnect(s) : Agent.connect(s, command: Agent.command))
            claudeConnected.toggle()
            if claudeConnected { Agent.requestPermission() }
        } catch {
            NSLog("TaskDock: could not update Claude Code settings: \(error)")
        }
    }

    func linkPhiSpace(_ id: UUID, _ title: String) { updateTemplate(id) { $0.phiSpace = title } }

    private func updateResume(_ id: UUID, _ change: (inout Resume) -> Void) {
        updateTemplate(id) { t in
            var r = t.resume ?? Resume()
            change(&r)
            t.resume = r
        }
    }

    private func updateTemplate(_ id: UUID, _ change: (inout Template) -> Void) {
        guard let i = templates.firstIndex(where: { $0.id == id }) else { return }
        change(&templates[i])
        saveTemplates()
    }

    private func runShortcut(_ name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        run("/usr/bin/shortcuts", ["run", name], wait: false)
    }

    func elapsed(_ s: Session) -> String { elapsedText(since: s.startedAt, now: now) }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
