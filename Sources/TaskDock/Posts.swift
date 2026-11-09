import AppKit

/// An X post saved for the monthly article: the link, the exact text, and your note.
struct Post: Codable, Identifiable, Equatable {
    var id: String
    var url: String
    var author: String
    var handle: String
    var text: String
    var postedAt: Date?
    var savedAt: Date
    var note: String
    /// The text is missing or was cut off ("Show more"); X's embed service fills it in.
    var partial: Bool
    /// The Obsidian note this post went into, once you pressed Start writing.
    var usedIn: String?

    // MARK: Rules (pure, tested)

    /// The post id and author handle in any x.com or twitter.com post link.
    static func ref(_ url: String) -> (id: String, handle: String)? {
        guard let c = URLComponents(string: url), let host = c.host?.lowercased(),
              ["x.com", "twitter.com"].contains(where: { host == $0 || host.hasSuffix("." + $0) }) else { return nil }
        let parts = c.path.split(separator: "/").map(String.init)
        guard parts.count >= 3, parts[1] == "status", !parts[2].isEmpty, parts[2].allSatisfy(\.isNumber),
              parts[0].allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { return nil }
        return (parts[2], parts[0])
    }

    static func canonical(handle: String, id: String) -> String { "https://x.com/\(handle)/status/\(id)" }

    /// Saving a post again keeps one entry: the best text wins (full over cut-off), and a note replaces the old one.
    static func merge(_ old: Post?, _ new: Post, note: String?) -> Post {
        var p = old ?? new
        if let old {
            if !new.text.isEmpty && (old.text.isEmpty || old.partial || !new.partial) {
                p.text = new.text
                p.partial = new.partial
            }
            if !new.author.isEmpty { p.author = new.author }
            if !new.handle.isEmpty { p.handle = new.handle; p.url = new.url }
            p.postedAt = new.postedAt ?? old.postedAt
        }
        if let note { p.note = note }
        return p
    }

    /// Lines the iPhone Shortcut appends: a post link, then optionally your thought after a space or tab.
    static func inbox(_ text: String) -> [(url: String, note: String)] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.trimmingCharacters(in: .whitespaces).split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" })
            guard let first = parts.first.map(String.init), ref(first) != nil else { return nil }
            return (first, parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : "")
        }
    }

    /// Fills in text, author and date from X's oEmbed reply (publish.twitter.com/oembed).
    static func fromEmbed(_ data: Data, base: Post) -> Post? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let html = json["html"] as? String,
              let p = html.range(of: #"<p[^>]*>"#, options: .regularExpression),
              let end = html.range(of: "</p>", range: p.upperBound..<html.endIndex) else { return nil }
        var post = base
        post.text = plain(String(html[p.upperBound..<end.lowerBound]))
        post.partial = false
        if let name = json["author_name"] as? String, !name.isEmpty { post.author = name }
        if let handle = (json["author_url"] as? String).flatMap(URL.init(string:))?.lastPathComponent, !handle.isEmpty { post.handle = handle }
        // The date is the last link's text, e.g. "March 21, 2006".
        if let a = html.range(of: #">([^<>]+)</a></blockquote>"#, options: .regularExpression) {
            let day = DateFormatter()
            day.locale = Locale(identifier: "en_US_POSIX")
            day.timeZone = TimeZone(identifier: "UTC")
            day.dateFormat = "MMMM d, yyyy"
            post.postedAt = day.date(from: String(html[a].dropFirst().dropLast("</a></blockquote>".count))) ?? base.postedAt
        }
        return post
    }

    private static func plain(_ html: String) -> String {
        var s = html.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        for (entity, char) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&mdash;", "—"), ("&nbsp;", " "), ("&amp;", "&")] {
            s = s.replacingOccurrences(of: entity, with: char)
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The month's note, e.g. "Posts – November 2026".
    static func noteTitle(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "LLLL yyyy"
        return "Posts – " + f.string(from: date)
    }

    /// The Obsidian note: each post quoted with its link and your take. Adds to `existing`, never replaces it.
    static func markdown(_ posts: [Post], title: String, existing: String?) -> String {
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = TimeZone(identifier: "UTC")
        day.dateFormat = "d MMM yyyy"
        let sections = posts.map { p in
            let date = p.postedAt.map { " · " + day.string(from: $0) } ?? ""
            let quote = (p.text.isEmpty ? "Text not captured yet." : p.text)
                .split(separator: "\n", omittingEmptySubsequences: false).map { "> " + $0 }.joined(separator: "\n")
            return "## \(p.author) (@\(p.handle))\(date)\n\n\(quote)\n\n\(p.url)\n\nMy take: \(p.note)\n"
        }.joined(separator: "\n")
        guard let existing, !existing.isEmpty else { return "# \(title)\n\n" + sections }
        return existing + (existing.hasSuffix("\n") ? "\n" : "\n\n") + sections
    }
}

/// The saved-posts list: saves from the browser extension and the iPhone Shortcut, review, and Start writing.
@MainActor
final class Posts: ObservableObject {
    static let shared = Posts()

    @Published var posts: [Post] = [] {
        didSet { if posts != oldValue { save(); if posts.map(\.id) != oldValue.map(\.id) { onIDsChanged() } } }
    }
    /// Reading the iPhone inbox needs iCloud Drive access, so it's off until you set it up.
    @Published var phoneEnabled = UserDefaults.standard.bool(forKey: "postsPhone") {
        didSet { UserDefaults.standard.set(phoneEnabled, forKey: "postsPhone"); readInbox() }
    }
    var onIDsChanged: () -> Void = {}

    private var file: URL { Store.dir.appendingPathComponent("posts.json") }
    /// Post ids the inbox already handed over, so a post you deleted doesn't come back from it.
    private var inboxSeen: Set<String> = []
    private var inboxSeenFile: URL { Store.dir.appendingPathComponent("posts-inbox-seen.json") }
    /// Posts already sent to the embed service this launch. A failure (offline, deleted post) is retried next launch.
    private var tried: Set<String> = []
    static let inboxFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Mobile Documents/iCloud~is~workflow~my~workflows/Documents/TaskDock/inbox.txt")

    var unused: Int { posts.filter { $0.usedIn == nil }.count }

    func boot() {
        if let data = try? Data(contentsOf: file) {
            do { posts = try JSONDecoder().decode([Post].self, from: data) } catch { NSLog("TaskDock: could not read posts.json: \(error)") }
        }
        inboxSeen = (try? JSONDecoder().decode(Set<String>.self, from: Data(contentsOf: inboxSeenFile))) ?? []
        tick()
    }

    /// Runs on the app's timer: new iPhone saves, and text still missing.
    func tick() {
        readInbox()
        for p in posts where p.partial { fetchText(p.id) }
    }

    /// A save (or a note) from the browser extension. Only the id and handle from the post's own link are trusted.
    func save(from msg: [String: Any]) {
        guard let ref = (msg["url"] as? String).flatMap(Post.ref), msg["id"] as? String == ref.id else { return }
        let text = String((msg["text"] as? String ?? "").prefix(30_000))
        let post = Post(id: ref.id, url: Post.canonical(handle: ref.handle, id: ref.id),
                        author: String((msg["author"] as? String ?? "").prefix(200)), handle: ref.handle, text: text,
                        postedAt: (msg["postedAt"] as? String).flatMap { ISO8601DateFormatter.withFractions.date(from: $0) },
                        savedAt: Date(), note: "", partial: text.isEmpty || msg["partial"] as? Bool == true)
        add(post, note: (msg["note"] as? String).map { String($0.prefix(5000)) })
    }

    private func add(_ post: Post, note: String?) {
        if let i = posts.firstIndex(where: { $0.id == post.id }) {
            posts[i] = Post.merge(posts[i], post, note: note)
        } else {
            var p = Post.merge(nil, post, note: note)
            if p.author.isEmpty { p.author = p.handle } // a link-only save; the embed fetch fills in the name
            posts.insert(p, at: 0)
        }
        if posts.first(where: { $0.id == post.id })?.partial == true { fetchText(post.id) }
    }

    func delete(_ id: String) { posts.removeAll { $0.id == id } }

    private func readInbox() {
        guard phoneEnabled, let text = try? String(contentsOf: Self.inboxFile, encoding: .utf8) else { return }
        var seen = inboxSeen
        for line in Post.inbox(text) {
            guard let ref = Post.ref(line.url), !seen.contains(ref.id) else { continue }
            seen.insert(ref.id)
            add(Post(id: ref.id, url: Post.canonical(handle: ref.handle, id: ref.id), author: ref.handle, handle: ref.handle,
                     text: "", postedAt: nil, savedAt: Date(), note: "", partial: true), note: line.note.isEmpty ? nil : line.note)
        }
        if seen != inboxSeen {
            inboxSeen = seen
            try? JSONEncoder().encode(inboxSeen).write(to: inboxSeenFile, options: .atomic)
        }
    }

    /// Asks X's public embed service for the post's text. Sends only the post's public link.
    private func fetchText(_ id: String) {
        guard !tried.contains(id), let post = posts.first(where: { $0.id == id }) else { return }
        #if DEBUG
        if ProcessInfo.processInfo.environment["TASKDOCK_NO_EMBED"] != nil { return } // tests stay offline
        #endif
        var c = URLComponents(string: "https://publish.twitter.com/oembed")!
        c.queryItems = [.init(name: "url", value: post.url), .init(name: "omit_script", value: "1"), .init(name: "dnt", value: "true")]
        tried.insert(id)
        Task {
            let data = try? await URLSession.shared.data(from: c.url!).0
            guard let data, let i = posts.firstIndex(where: { $0.id == id }), posts[i].partial,
                  let filled = Post.fromEmbed(data, base: posts[i]) else { return }
            posts[i] = Post.merge(posts[i], filled, note: nil)
        }
    }

    // MARK: Start writing

    /// Writes the chosen posts into this month's note in the Obsidian vault and opens it.
    /// Without a vault, the note is copied to the clipboard instead. Returns what happened, for the window.
    func startWriting(_ ids: Set<String>, now: Date = Date()) -> String {
        let chosen = posts.filter { ids.contains($0.id) }.reversed() // oldest first reads like the month went
        guard !chosen.isEmpty else { return "" }
        let title = Post.noteTitle(now)
        guard let vault = Self.vault() else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(Post.markdown(Array(chosen), title: title, existing: nil), forType: .string)
            mark(ids, title)
            return "No Obsidian vault found, so the note was copied to the clipboard."
        }
        let folder = vault.appendingPathComponent("Articles", isDirectory: true)
        let url = folder.appendingPathComponent(title + ".md")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let existing = try? String(contentsOf: url, encoding: .utf8)
            try Post.markdown(Array(chosen), title: title, existing: existing).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            return "Couldn't write the note: \(error.localizedDescription)"
        }
        mark(ids, title)
        if ProcessInfo.processInfo.environment["TASKDOCK_VAULT"] == nil { NSWorkspace.shared.open(Snapshot.obsidianLink(url.path)) } // tests don't open Obsidian
        return ""
    }

    private func mark(_ ids: Set<String>, _ title: String) {
        for i in posts.indices where ids.contains(posts[i].id) { posts[i].usedIn = title }
    }

    /// The vault Obsidian opened most recently (TASKDOCK_VAULT overrides it for tests).
    static func vault() -> URL? {
        if let v = ProcessInfo.processInfo.environment["TASKDOCK_VAULT"] { return URL(fileURLWithPath: v, isDirectory: true) }
        let config = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/obsidian/obsidian.json")
        guard let data = try? Data(contentsOf: config),
              let vaults = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["vaults"] as? [String: [String: Any]],
              let path = vaults.values.max(by: { ($0["ts"] as? Double ?? 0) < ($1["ts"] as? Double ?? 0) })?["path"] as? String
        else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        do { try enc.encode(posts).write(to: file, options: .atomic) } catch { NSLog("TaskDock: could not save posts.json: \(error)") }
    }
}

extension ISO8601DateFormatter {
    /// The browser's `time[datetime]`, e.g. "2026-11-09T08:15:00.000Z".
    static let withFractions: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
