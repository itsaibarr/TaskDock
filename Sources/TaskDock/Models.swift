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
