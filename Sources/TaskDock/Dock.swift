import Foundation

/// The Dock has no public API. Like dockutil, we rewrite its preferences and restart it.
/// The snapshot is the whole exported domain, kept in the session, so finishing a task puts
/// back exactly what was there.
///
/// Gotcha (found in live testing): a Dock that was restarted only a few seconds ago saves its
/// own state again when killed, overwriting ours. So changes run in order on a background
/// queue, wait for the Dock to settle first, and are read back and retried if they didn't stick.
enum Dock {
    private static let domain = "com.apple.dock"
    private static let queue = DispatchQueue(label: "taskdock.dock")
    private static var lastRelaunch = Date.distantPast // only touched on `queue`
    private static let settle: TimeInterval = 6

    /// Waits for pending Dock changes, so it never snapshots a half-applied Dock.
    static func snapshot() -> Data? { queue.sync { export() } }

    private static func export() -> Data? {
        let data = capture("/usr/bin/defaults", ["export", domain, "-"])
        // Never touch the Dock if we couldn't read it.
        guard let data, (try? PropertyListSerialization.propertyList(from: data, format: nil)) is [String: Any] else { return nil }
        return data
    }

    /// Shows only `apps` in the Dock; hidden apps that are still running are drawn dimmed.
    static func apply(_ apps: [AppRef], over snapshot: Data, backup: URL) {
        if !FileManager.default.fileExists(atPath: backup.path) {
            try? snapshot.write(to: backup)
        }
        guard var prefs = try? PropertyListSerialization.propertyList(from: snapshot, format: nil) as? [String: Any] else { return }
        prefs["persistent-apps"] = apps.map(tile)
        prefs["show-hidden"] = true
        prefs["show-recents"] = false
        guard let data = try? PropertyListSerialization.data(fromPropertyList: prefs, format: .binary, options: 0) else { return }
        queue.async { load(data) }
    }

    static func restore(_ snapshot: Data) { queue.async { load(snapshot) } }

    /// Bundle IDs in Dock order; the Dock rewrites other tile fields, so compare only these.
    static func appIDs(_ prefs: Data?) -> [String] {
        let dict = prefs.flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] }
        let tiles = dict?["persistent-apps"] as? [[String: Any]] ?? []
        return tiles.map { (($0["tile-data"] as? [String: Any])?["bundle-identifier"] as? String) ?? ($0["tile-type"] as? String ?? "?") }
    }

    static func tile(_ app: AppRef) -> [String: Any] {
        [
            "GUID": Int(UInt32.random(in: 1...UInt32.max)),
            "tile-type": "file-tile",
            "tile-data": [
                "bundle-identifier": app.bundleID,
                "file-label": app.name,
                "file-type": 41,
                "file-data": [
                    "_CFURLString": URL(fileURLWithPath: app.path, isDirectory: true).absoluteString,
                    "_CFURLStringType": 15,
                ],
            ] as [String: Any],
        ]
    }

    private static func load(_ data: Data) {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("taskdock-dock-\(UUID().uuidString).plist")
        guard (try? data.write(to: file)) != nil else { return }
        defer { try? FileManager.default.removeItem(at: file) }
        let want = appIDs(data)
        for attempt in 1...4 {
            let wait = settle - Date().timeIntervalSince(lastRelaunch)
            if wait > 0 { Thread.sleep(forTimeInterval: wait) }
            run("/usr/bin/defaults", ["import", domain, file.path])
            run("/usr/bin/killall", ["Dock"])
            lastRelaunch = Date()
            Thread.sleep(forTimeInterval: 1.5)
            if appIDs(export()) == want { return }
            NSLog("TaskDock: Dock change didn't stick, retrying (\(attempt))")
        }
        NSLog("TaskDock: Dock change failed; backup is in ~/Library/Application Support/TaskDock/dock-original.plist")
    }

    private static func capture(_ path: String, _ args: [String]) -> Data? {
        let p = Process()
        let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = pipe
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return p.terminationStatus == 0 ? data : nil
    }
}
