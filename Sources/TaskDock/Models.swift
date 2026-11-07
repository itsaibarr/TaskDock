import AppKit

struct AppRef: Codable, Hashable, Identifiable {
    var bundleID: String
    var name: String
    var path: String
    var id: String { bundleID }

    init(bundleID: String, name: String, path: String) {
        self.bundleID = bundleID
        self.name = name
        self.path = path
    }

    init?(_ app: NSRunningApplication) {
        guard let id = app.bundleIdentifier, let url = app.bundleURL else { return nil }
        self.init(bundleID: id, name: app.localizedName ?? url.deletingPathExtension().lastPathComponent, path: url.path)
    }

    init?(url: URL) {
        guard let id = Bundle(url: url)?.bundleIdentifier else { return nil }
        self.init(bundleID: id, name: url.deletingPathExtension().lastPathComponent, path: url.path)
    }

    /// Current location of the app, falling back to where it was when saved.
    var url: URL {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) ?? URL(fileURLWithPath: path)
    }

    /// Any app that can open web links counts as a browser.
    var isBrowser: Bool { AppRef.browserIDs.contains(bundleID) }
    /// A browser the TaskDock extension manages (fresh window, saved tabs). Phi keeps tabs in its own Spaces.
    var usesExtension: Bool { isBrowser && bundleID != Phi.id }

    static let browserIDs = Set(
        NSWorkspace.shared.urlsForApplications(toOpen: URL(string: "https://example.com")!)
            .compactMap { Bundle(url: $0)?.bundleIdentifier }
    )
}

struct Template: Codable, Hashable, Identifiable {
    var id = UUID()
    var name = "New task"
    var emoji = "🎯"
    var apps: [AppRef] = []
    var startShortcut = ""
    var endShortcut = ""
    var lastStopNote = ""
    /// What was open when the task last ended; reopened on the next start. Optional so older files load.
    var resume: Resume?
    /// Phi Space to switch to on start (by title). Nil: the Space named like the template, if any.
    var phiSpace: String?

    var usesPhi: Bool { apps.contains { $0.bundleID == Phi.id } }
}

/// Snapshot of a task's working state: browser tabs plus files and notes, each with the app that had it open.
struct Resume: Codable, Hashable {
    var savedAt = Date()
    var tabs: [String] = []
    var items: [Item] = []
    /// AeroSpace workspace each app was on (bundle ID → workspace). Optional so older files load.
    var workspaces: [String: String]?

    struct Item: Codable, Hashable {
        var app: String // bundle ID
        var url: URL

        /// "Calculus" for /Books/Calculus.pdf; the note name for an obsidian:// link.
        var title: String {
            let path = url.isFileURL ? url.path
                : URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "path" }?.value ?? url.absoluteString
            return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        }
    }

    var isEmpty: Bool { tabs.isEmpty && items.isEmpty }
}

struct Session: Codable {
    var id = UUID()
    var template: Template
    var goal: String
    var startedAt = Date()
    /// Apps that were visible before the task, unhidden on finish.
    var visibleApps: [String]
    /// Exported com.apple.dock preferences from before the task.
    var dock: Data?
    /// Apps TaskDock opened for this task; they're quit when it ends. Optional so older files load.
    var launched: [String]?
}

func elapsedText(since start: Date, now: Date) -> String {
    let m = max(0, Int(now.timeIntervalSince(start) / 60))
    return m < 60 ? "\(m)m" : "\(m / 60)h \(String(format: "%02d", m % 60))m"
}

/// Runs a command and waits for it.
@discardableResult
func run(_ path: String, _ args: [String], wait: Bool = true) -> Int32 {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    do { try p.run() } catch { NSLog("TaskDock: failed to run \(path): \(error)"); return -1 }
    guard wait else { return 0 }
    p.waitUntilExit()
    return p.terminationStatus
}

/// Runs an AppleScript and returns what it printed. Blocking.
func osascript(_ script: String) -> Data? { capture("/usr/bin/osascript", ["-e", script]) }

/// Runs a command and returns what it printed, or nil if it failed (its error is logged).
func capture(_ path: String, _ args: [String]) -> Data? {
    let p = Process(), out = Pipe(), err = Pipe()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    p.standardOutput = out
    p.standardError = err
    do { try p.run() } catch { return nil }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    let problem = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    p.waitUntilExit()
    guard p.terminationStatus == 0 else {
        NSLog("TaskDock: \(URL(fileURLWithPath: path).lastPathComponent) failed: \(problem.prefix(300))")
        return nil
    }
    return data
}
