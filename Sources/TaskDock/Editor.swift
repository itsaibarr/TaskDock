import SwiftUI

struct EditorView: View {
    @EnvironmentObject var store: Store
    @State private var dragging: UUID?

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                Menu {
                    Button("From Current Setup") { store.addTemplate(store.captureTemplate()) }
                    Button("Empty Template") { store.addTemplate(Template()) }
                } label: {
                    Label("New Template", systemImage: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(Theme.accent, in: Capsule())
                        .contentShape(Capsule())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .padding(.horizontal, 10).padding(.bottom, 10)

                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(store.templates) { t in
                            SidebarRow(t: t, selected: store.editorSelection == t.id) {
                                store.editorSelection = t.id
                            }
                            .contextMenu {
                                Button("Edit", systemImage: "pencil") { store.editorSelection = t.id }
                                Button("Delete", systemImage: "trash", role: .destructive) { store.deleteTemplate(t.id) }
                            }
                            .modifier(ReorderDrag(id: t.id, step: 48, items: $store.templates, dragging: $dragging))
                        }
                    }
                    .padding(.horizontal, 10)
                }

                BrowserStatusCard(connected: store.browsers > 0).padding(10)
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 300)
        } detail: {
            Group {
                if let i = store.templates.firstIndex(where: { $0.id == store.editorSelection }) {
                    TemplateForm(t: $store.templates[i], browsers: store.browsers) {
                        store.deleteTemplate(store.templates[i].id)
                    }
                    .id(store.templates[i].id) // fresh scroll position per template
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "square.stack").font(.system(size: 26)).foregroundStyle(.tertiary)
                        Text(store.templates.isEmpty ? "No templates yet" : "No template selected")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Open the apps a task needs, then choose New Template → From Current Setup.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center).frame(maxWidth: 260)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.canvas)
        }
        .navigationTitle("")
        .onChange(of: store.templates) { store.saveTemplates() }
        .onAppear {
            if store.editorSelection == nil { store.editorSelection = store.templates.first?.id }
        }
    }
}

/// Footer card, like the reference's account card: shows whether the browser extension is connected.
private struct BrowserStatusCard: View {
    let connected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "globe")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(connected ? Theme.accent : Color.orange, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text("Browser extension").font(.system(size: 13, weight: .medium))
                Text(connected ? "Connected" : "Not connected").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .card(radius: 12)
    }
}

/// Emoji tile, name, and a one-line subtitle, like the reference's conversation list.
private struct SidebarRow: View {
    let t: Template
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(t.emoji).font(.system(size: 17))
                    .frame(width: 34, height: 34)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.border))
                VStack(alignment: .leading, spacing: 1) {
                    Text(t.name.isEmpty ? "Untitled" : t.name).font(.system(size: 13, weight: .medium))
                    Text(t.lastStopNote.isEmpty ? "\(t.apps.count) apps" : t.lastStopNote)
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(selected ? Theme.selected : hovering ? Theme.hover : .clear,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.quick, value: hovering)
        .animation(Theme.quick, value: selected)
    }
}

struct TemplateForm: View {
    @Binding var t: Template
    let browsers: Int
    let onDelete: () -> Void
    @State private var confirmDelete = false
    @State private var choosingIcon = false
    @State private var choosingApps = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                section("Apps", footer: "Only these apps stay visible and in the Dock. Everything else is hidden until you finish.") {
                    ForEach(t.apps) { app in
                        HStack(spacing: 10) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                                .resizable().frame(width: 22, height: 22)
                            Text(app.name)
                            Spacer()
                            Button { t.apps.removeAll { $0.id == app.id } } label: {
                                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                                    .frame(width: 20, height: 20)
                                    .background(Theme.field, in: Circle())
                            }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                            .help("Remove \(app.name)")
                        }
                        .padding(.horizontal, 14).frame(height: 44)
                        Divider().padding(.leading, 46).padding(.trailing, 14)
                    }
                    Button { choosingApps = true } label: {
                        Label("Choose Apps…", systemImage: "plus").frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain).foregroundStyle(Theme.accent)
                    .padding(.horizontal, 14).frame(height: 40)
                    .popover(isPresented: $choosingApps, arrowEdge: .bottom) {
                        AppChooser(apps: $t.apps, listHeight: 300).padding(12).frame(width: 360)
                    }
                }

                if t.apps.contains(where: \.usesExtension) {
                    section("Browser") {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("A fresh browser window opens for the task. Your other windows are minimized and their tabs paused until you finish.",
                                  systemImage: "macwindow.badge.plus")
                            if browsers == 0 {
                                Label("The TaskDock browser extension isn’t connected.", systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(.orange)
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                section("Apple Shortcuts", footer: "Shortcut names to run, for example ones that turn a Focus on and off.") {
                    labeled("On start") { TextField("", text: $t.startShortcut, prompt: Text("None")) }
                    Divider().padding(.horizontal, 14)
                    labeled("On finish") { TextField("", text: $t.endShortcut, prompt: Text("None")) }
                }

                if !t.lastStopNote.isEmpty {
                    section("Where You Stopped") {
                        labeled("Note") { TextField("", text: $t.lastStopNote, axis: .vertical) }
                    }
                }

                HStack {
                    Spacer()
                    Button("Delete Template…", role: .destructive) { confirmDelete = true }
                        .buttonStyle(.plain).foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 28).padding(.vertical, 24)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
        .confirmationDialog("Delete “\(t.name)”?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive, action: onDelete)
        } message: {
            Text("This can’t be undone.")
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Button { choosingIcon = true } label: {
                Text(t.emoji).font(.system(size: 40))
                    .frame(width: 76, height: 76)
                    .card(radius: 20)
            }
            .buttonStyle(.plain)
            .help("Choose an icon")
            .popover(isPresented: $choosingIcon, arrowEdge: .bottom) {
                EmojiGrid(emoji: $t.emoji) { choosingIcon = false }.padding(12).frame(width: 340)
            }
            TextField("", text: $t.name, prompt: Text("Template name"))
                .textFieldStyle(.plain)
                .font(.system(size: 20, weight: .semibold))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func section<Content: View>(_ title: String, footer: String? = nil,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 13, weight: .semibold)).padding(.leading, 4)
            VStack(alignment: .leading, spacing: 0) { content() }.card()
            if let footer {
                Text(footer).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).padding(.leading, 4)
            }
        }
    }

    /// "Label | grey field" row, like the reference's Name/Label rows.
    private func labeled<F: View>(_ label: String, @ViewBuilder field: () -> F) -> some View {
        HStack(spacing: 12) {
            Text(label).frame(width: 80, alignment: .leading)
            field().textFieldStyle(FilledFieldStyle())
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }
}
