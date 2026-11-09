import SwiftUI

/// The Saved Posts window: review what you saved from X, add your take, and start writing the article.
struct PostsView: View {
    @ObservedObject var posts = Posts.shared
    @State private var showAll = false
    /// New posts you unticked for this article. Everything else new goes in.
    @State private var excluded: Set<String> = []
    @State private var message = ""
    @State private var phoneHelp = false

    private var visible: [Post] { showAll ? posts.posts : posts.posts.filter { $0.usedIn == nil } }
    private var chosen: Set<String> { Set(posts.posts.filter { $0.usedIn == nil && !excluded.contains($0.id) }.map(\.id)) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Saved Posts").font(.system(size: 20, weight: .semibold))
                Picker("", selection: $showAll) {
                    Text("New").tag(false)
                    Text("All").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 120)
                Spacer()
                Button {
                    message = posts.startWriting(chosen)
                    excluded = []
                } label: {
                    Label(chosen.isEmpty ? "Start writing" : "Start writing (\(chosen.count))", systemImage: "square.and.pencil")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 14).frame(height: 30)
                        .background(Theme.accent.opacity(chosen.isEmpty ? 0.4 : 1), in: Capsule())
                }
                .buttonStyle(.plain).disabled(chosen.isEmpty)
                .help("Adds the ticked posts to this month's note in Obsidian (Articles folder) and opens it.")
            }
            .padding(.horizontal, 20).padding(.top, 28).padding(.bottom, 12)

            if !message.isEmpty {
                Text(message).font(.system(size: 12)).foregroundStyle(Theme.note)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.bottom, 8)
            }

            if visible.isEmpty {
                VStack(spacing: 6) {
                    Text(posts.posts.isEmpty ? "No saved posts yet" : "Nothing new since your last article")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Click ◎ under any post on x.com, or share a post to TaskDock from your iPhone.")
                        .font(.system(size: 13)).foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(visible) { p in
                            PostRow(post: p, included: p.usedIn == nil ? Binding(
                                get: { !excluded.contains(p.id) },
                                set: { if $0 { excluded.remove(p.id) } else { excluded.insert(p.id) } }) : nil,
                                    note: Binding(
                                get: { posts.posts.first { $0.id == p.id }?.note ?? "" },
                                set: { n in if let i = posts.posts.firstIndex(where: { $0.id == p.id }) { posts.posts[i].note = n } }),
                                    delete: { posts.delete(p.id) })
                        }
                    }
                    .padding(.horizontal, 20).padding(.bottom, 16)
                }
            }

            HStack {
                Button(posts.phoneEnabled ? "Saving from iPhone is on" : "Save from iPhone…") { phoneHelp = true }
                    .buttonStyle(.link)
                Spacer()
                Text("\(posts.posts.count) saved · \(posts.unused) new").foregroundStyle(Theme.muted)
            }
            .font(.system(size: 12)).padding(.horizontal, 20).padding(.vertical, 10)
            .overlay(alignment: .top) { Divider() }
        }
        .background(Theme.canvas)
        .frame(minWidth: 560, minHeight: 420)
        .sheet(isPresented: $phoneHelp) { PhoneHelp(enabled: $posts.phoneEnabled) }
    }
}

private struct PostRow: View {
    let post: Post
    let included: Binding<Bool>?
    let note: Binding<String>
    let delete: () -> Void

    private static let day: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeZone = TimeZone(identifier: "UTC") // X gives the day in UTC for phone saves
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let included {
                Toggle("", isOn: included).toggleStyle(.checkbox).labelsHidden()
                    .help("Include in the next Start writing")
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(post.author).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text("@" + post.handle + (post.postedAt.map { " · " + Self.day.string(from: $0) } ?? ""))
                        .font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1)
                    Spacer()
                    if let used = post.usedIn {
                        Text(used).font(.system(size: 11)).foregroundStyle(Theme.muted)
                            .padding(.horizontal, 7).padding(.vertical, 2).background(Theme.field, in: Capsule())
                    }
                    Link(destination: URL(string: post.url)!) { Image(systemName: "arrow.up.right.square") }
                        .help("Open on X")
                    Button(action: delete) { Image(systemName: "trash") }.buttonStyle(.plain)
                        .foregroundStyle(Theme.muted).help("Delete")
                }
                Text(post.text.isEmpty ? "Text not captured yet. It's fetched from X when you're online." : post.text)
                    .font(.system(size: 13)).foregroundStyle(post.text.isEmpty ? Theme.muted : .primary)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                TextField("", text: note, prompt: Text("My take…").foregroundStyle(Theme.muted), axis: .vertical)
                    .textFieldStyle(.plain).font(.system(size: 13)).lineLimit(1...8)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(Theme.field, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.border))
    }
}

/// How to set up the iPhone Shortcut, and the switch that lets TaskDock read what it saves.
private struct PhoneHelp: View {
    @Binding var enabled: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Save posts from your iPhone").font(.system(size: 17, weight: .semibold))
            Text("Make this Shortcut once in the Shortcuts app on your iPhone or iPad:").font(.system(size: 13))
            VStack(alignment: .leading, spacing: 8) {
                step(1, "New Shortcut, named “Save to TaskDock”. In its details, turn on Show in Share Sheet and allow URLs.")
                step(2, "Add Ask for Input: Text, prompt “Thought? (optional)”.")
                step(3, "Add Text with: Shortcut Input, a space, then Provided Input.")
                step(4, "Add Append to Text File: the Text from step 3, file path TaskDock/inbox.txt, Make New Line on.")
                step(5, "In the X app, tap Share on a post, then Save to TaskDock.")
            }
            Text("The file is in iCloud Drive › Shortcuts. TaskDock checks it every 20 seconds while your Mac is on, and only reads it. macOS may ask once to let TaskDock use iCloud Drive.")
                .font(.system(size: 12)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            Toggle("Read saves from iPhone", isOn: $enabled)
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 460)
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(n).").font(.system(size: 13, weight: .semibold)).frame(width: 16, alignment: .trailing)
            Text(text).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
        }
    }
}
