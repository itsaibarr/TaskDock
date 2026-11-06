import AppKit

@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    @Published var templates: [Template] = []
    @Published var session: Session?
    @Published var now = Date()
    @Published var browsers = 0
    @Published var editorSelection: UUID?

    let bridge = Bridge()

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
        templates = load([Template].self, from: templatesFile) ?? []
        // A session that survived a crash or quit is resumed, so Finish can still restore everything.
        session = load(Session.self, from: sessionFile)
        bridge.stateMessage = { [weak self] in self?.stateMessage ?? [:] }
        bridge.onBrowsersChanged = { [weak self] n in self?.browsers = n }
        bridge.start()
        Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { _ in
            MainActor.assumeIsolated { Store.shared.now = Date() }
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
            "browser": s.template.apps.contains(where: \.isBrowser),
        ] as [String: Any]]
    }

    func start(_ t: Template, goal: String) {
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        var visible = running.filter { !$0.isHidden }.compactMap(\.bundleIdentifier)
        var dock: Data? // the "home" Dock to return to on finish

        if let prev = session {
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

        // Save before changing anything, so a crash mid-way can still be undone.
        session = Session(template: t, goal: goal, visibleApps: visible, dock: dock)
        saveSession()

        let keep = Set(t.apps.map(\.bundleID)).union([Bundle.main.bundleIdentifier ?? ""])
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
        for app in running where !keep.contains(app.bundleIdentifier ?? "") { app.hide() }

        if let dock { Dock.apply(t.apps, over: dock, backup: dockBackupFile) }
        bridge.broadcast(stateMessage)
        runShortcut(t.startShortcut)
    }

    func finish(note: String) {
        guard let s = session else { return }
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
        if !note.isEmpty, let i = templates.firstIndex(where: { $0.id == s.template.id }) {
            templates[i].lastStopNote = note
            saveTemplates()
        }
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
