import AppKit

/// Reads what a task's apps have open, so the next start can reopen it.
/// Browser tabs come from the extension instead (see Bridge).
enum Snapshot {
    static let obsidianID = "md.obsidian"

    /// Files open in the template's running apps, and the apps that couldn't be read (permission
    /// denied, a dialog, a timeout), whose earlier saved files should be kept. Call off the main thread:
    /// the first AppleScript call to each app waits for the user to answer macOS's permission prompt.
    static func items(_ apps: [AppRef]) -> (items: [Resume.Item], unread: Set<String>) {
        var items: [Resume.Item] = [], unread = Set<String>()
        for app in apps where isRunning(app.bundleID) && !app.isBrowser {
            let urls: [URL]?
            if app.bundleID == obsidianID {
                urls = obsidianNote().map { [$0] }
            } else if Bundle(url: app.url)?.object(forInfoDictionaryKey: "NSAppleScriptEnabled") as? Bool == true {
                urls = documents(of: app.bundleID)
            } else {
                continue
            }
            if let urls { items += urls.map { Resume.Item(app: app.bundleID, url: $0) } } else { unread.insert(app.bundleID) }
        }
        return (items, unread)
    }

    /// Uses NSWorkspace's list, read on the main thread where it's kept current. In testing,
    /// `NSRunningApplication.runningApplications(withBundleIdentifier:)` sometimes reported running apps as gone.
    static func running(_ bundleID: String) -> [NSRunningApplication] {
        let find = { NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == bundleID && !$0.isTerminated } }
        return Thread.isMainThread ? find() : DispatchQueue.main.sync(execute: find)
    }

    static func isRunning(_ bundleID: String) -> Bool { !running(bundleID).isEmpty }

    /// Files of the app's open documents, via the standard AppleScript suite (Preview, TextEdit, Pages…).
    private static func documents(of bundleID: String) -> [URL]? {
        let script = """
        set out to ""
        with timeout of 20 seconds
        tell application id "\(bundleID)"
            repeat with d in documents
                try
                    set out to out & POSIX path of (file of d as alias) & linefeed
                on error
                    try
                        set out to out & (path of d) & linefeed
                    end try
                end try
            end repeat
        end tell
        end timeout
        return out
        """
        guard let out = osascript(script) else { return nil }
        return String(decoding: out, as: UTF8.self)
            .split(separator: "\n").map(String.init)
            .filter { $0.hasPrefix("/") && FileManager.default.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    // MARK: Obsidian (not scriptable; its open notes are in each vault's workspace.json)

    private static func obsidianNote() -> URL? {
        let config = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/obsidian/obsidian.json")
        guard let data = try? Data(contentsOf: config),
              let vaults = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["vaults"] as? [String: [String: Any]]
        else { return nil }
        // Most recently opened vault first ("ts" is when Obsidian last opened it).
        let open = vaults.values.filter { $0["open"] as? Bool == true }
            .sorted { ($0["ts"] as? Double ?? 0) > ($1["ts"] as? Double ?? 0) }
        for vault in open {
            guard let root = vault["path"] as? String,
                  let ws = try? Data(contentsOf: URL(fileURLWithPath: root).appendingPathComponent(".obsidian/workspace.json")),
                  let file = activeFile(ws) else { continue }
            return obsidianLink(URL(fileURLWithPath: root).appendingPathComponent(file).path)
        }
        return nil
    }

    /// Vault-relative path of the note in the focused tab, or the most recently opened one.
    static func activeFile(_ workspace: Data) -> String? {
        guard let ws = try? JSONSerialization.jsonObject(with: workspace) as? [String: Any] else { return nil }
        func leaves(_ node: Any?) -> [[String: Any]] {
            guard let n = node as? [String: Any] else { return [] }
            return (n["type"] as? String == "leaf" ? [n] : []) + ((n["children"] as? [Any]) ?? []).flatMap(leaves)
        }
        let active = ["main", "left", "right"].flatMap { leaves(ws[$0]) }.first { $0["id"] as? String == ws["active"] as? String }
        let file = ((active?["state"] as? [String: Any])?["state"] as? [String: Any])?["file"] as? String
        return file ?? (ws["lastOpenFiles"] as? [String])?.first
    }

    static func obsidianLink(_ path: String) -> URL {
        var c = URLComponents(string: "obsidian://open")!
        c.queryItems = [URLQueryItem(name: "path", value: path)]
        return c.url!
    }

    /// Reopens saved files and notes in the apps that had them. Files an app already has open are
    /// skipped: Preview would open a second copy instead of showing the first.
    static func reopen(_ items: [Resume.Item]) {
        DispatchQueue.global().async {
            let scriptable = Set(items.filter(\.url.isFileURL).map(\.app)).filter(isRunning)
            let open = Set(scriptable.flatMap { documents(of: $0) ?? [] }.map(\.standardizedFileURL))
            for item in items where !item.url.isFileURL
                || (FileManager.default.fileExists(atPath: item.url.path) && !open.contains(item.url.standardizedFileURL)) {
                guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: item.app) else { continue }
                let cfg = NSWorkspace.OpenConfiguration()
                cfg.activates = false
                NSWorkspace.shared.open([item.url], withApplicationAt: app, configuration: cfg)
            }
        }
    }
}

