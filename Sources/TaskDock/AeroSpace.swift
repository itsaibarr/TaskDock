import Foundation

/// AeroSpace tiling window manager: remembers which workspace each task app was on and puts it back.
/// Does nothing when AeroSpace isn't installed.
enum AeroSpace {
    static let cli = ["/opt/homebrew/bin/aerospace", "/usr/local/bin/aerospace"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }

    struct Window: Equatable { let id: String, app: String, workspace: String }

    static func windows() -> [Window] {
        guard let cli, let data = capture(cli, ["list-windows", "--all", "--format", "%{window-id}|%{app-bundle-id}|%{workspace}"])
        else { return [] }
        return parse(String(decoding: data, as: UTF8.self))
    }

    #if DEBUG
    static func title(of windowID: String) -> String {
        guard let cli, let data = capture(cli, ["list-windows", "--all", "--format", "%{window-id}|%{window-title}"]) else { return "" }
        return String(decoding: data, as: UTF8.self).split(separator: "\n")
            .first { $0.hasPrefix(windowID + "|") }.map { String($0.dropFirst(windowID.count + 1)) } ?? ""
    }
    #endif

    static func parse(_ text: String) -> [Window] {
        text.split(separator: "\n").compactMap { line in
            let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            return f.count == 3 && !f[2].isEmpty ? Window(id: f[0], app: f[1], workspace: f[2]) : nil
        }
    }

    /// Workspace of each app's first window. Blocking.
    static func workspaces(of apps: [String]) -> [String: String] {
        windows().reduce(into: [:]) { map, w in
            if apps.contains(w.app), map[w.app] == nil { map[w.app] = w.workspace }
        }
    }

    /// Moves the apps' windows to their saved workspaces as they appear (apps may still be launching),
    /// including documents reopened a moment later, and shows the workspace of `focus`. Each window is moved once, so moving it yourself afterwards sticks. Blocking.
    static func restore(_ saved: [String: String], focus: String?) {
        guard let cli, !saved.isEmpty else { return }
        var moved = Set<String>(), focused = false, quiet = 0
        for _ in 0..<20 { // up to about 10 s
            let all = windows(), fresh = all.filter { saved[$0.app] != nil && !moved.contains($0.id) }
            // Done once every app has a window and nothing new has appeared for a couple of seconds.
            quiet = fresh.isEmpty ? quiet + 1 : 0
            if quiet >= 4, Set(all.map(\.app)).isSuperset(of: saved.keys) { break }
            for w in fresh {
                let target = saved[w.app]!
                moved.insert(w.id)
                if w.workspace != target { _ = capture(cli, ["move-node-to-workspace", "--window-id", w.id, target]) }
                // Show the first app's workspace as soon as its window is there, not after the whole wait.
                if !focused, w.app == focus { _ = capture(cli, ["workspace", target]); focused = true }
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
    }
}
