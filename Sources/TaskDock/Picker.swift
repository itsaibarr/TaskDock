import SwiftUI

/// Spotlight-style panel: takes keyboard input without activating TaskDock or stealing the menu bar.
final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
enum Windows {
    private(set) static var picker: KeyPanel?
    /// Fixed panel size with room for the card to grow and cast its shadow. Transparent parts let clicks through.
    static let size = CGSize(width: 560, height: 540)

    static func togglePicker(switching: Bool = false) {
        if let p = picker, p.isVisible { closePicker(); return }
        let panel = picker ?? makePanel()
        picker = panel
        let host = NSHostingView(rootView:
            PickerView(switching: switching, close: closePicker).environmentObject(Store.shared))
        host.sizingOptions = [] // the card animates inside a fixed window; never resize the panel
        panel.contentView = host
        if let f = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: f.midX - size.width / 2, y: f.maxY - f.height * 0.18 - size.height))
        }
        panel.makeKeyAndOrderFront(nil)
    }

    /// Drops the view too, so a hidden picker never reacts to store changes.
    static func closePicker() {
        picker?.orderOut(nil)
        picker?.contentView = nil
    }

    private static func makePanel() -> KeyPanel {
        let p = KeyPanel(contentRect: NSRect(origin: .zero, size: size),
                         styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false // SwiftUI draws it; a window shadow would not follow the animated card
        p.level = .floating
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: p, queue: .main) { _ in
            MainActor.assumeIsolated { closePicker() }
        }
        return p
    }
}

/// Opens as a small pill (no animation: it's a hotkey). Clicking or typing springs it open into the list.
struct PickerView: View {
    @EnvironmentObject var store: Store
    @State var switching: Bool
    let close: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var ns
    @State private var expanded = false
    @State private var revealed = false
    @State private var query = ""
    @State private var index = 0
    @State private var chosenID: UUID?
    @State private var editing: Editing?
    @State private var dragging: UUID?
    @State private var goal = ""
    /// Calendar event happening now; read once when the picker opens.
    @State private var suggestion: CalendarSuggestion?
    @State private var note = ""
    @FocusState private var focused: Bool

    /// Shown above the templates while not searching. Takes row index 0 when present.
    private var suggested: CalendarSuggestion? { query.isEmpty ? suggestion : nil }
    private var lead: Int { suggested == nil ? 0 : 1 }

    private var matches: [Template] {
        query.isEmpty ? store.templates : store.templates.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.emoji == query
        }
    }

    /// Inline editors on the start screen. Inline, not popovers: a popover would take key and close the panel.
    private enum Editing { case icon, apps }

    private var showsList: Bool { (store.session == nil || switching) && chosenID == nil }
    private var isOpen: Bool { expanded || !showsList }
    /// The reference's overshooting spring: only for the pill opening up.
    private var morph: Animation { reduceMotion ? .easeOut(duration: 0.15) : Theme.morph }
    /// Everything else inside the open card settles without overshoot.
    private var settle: Animation { reduceMotion ? .easeOut(duration: 0.15) : Theme.settle }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let s = store.session, !switching {
                finishView(s)
            } else if let i = store.templates.firstIndex(where: { $0.id == chosenID }) {
                goalView(i)
            } else {
                listView
            }
        }
        .padding(6) // glass rim around the white cloud
        .frame(width: isOpen ? 480 : 320, alignment: .topLeading)
        .glass(radius: 24)
        .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
        .padding(.top, 24)
        .frame(width: Windows.size.width, height: Windows.size.height, alignment: .top)
        .onExitCommand { editing == nil ? close() : toggle(nil) }
        .onChange(of: store.templates) { store.saveTemplates() }
        .onAppear { suggestion = CalendarFeed.shared.suggestion(for: store.templates) }
        .onReceive(NotificationCenter.default.publisher(for: Debug.pickerStep)) { n in
            switch n.object as? String {
            case "expand": expand()
            case "choose": if let t = matches.first { choose(t) }
            case "icon": toggle(.icon)
            case "apps": toggle(.apps)
            default: break
            }
        }
    }

    // MARK: List

    /// Rows shown before the list scrolls; keeps the card inside the fixed panel.
    private var maxRows: Int { 8 - 2 * lead } // the suggestion and its labels take about two rows
    /// Row the arrow keys moved to; hover doesn't set it, so pointing at a row never scrolls the list.
    @State private var keyboardTarget: AnyHashable?
    private static let newRowID = "new-template"

    @ViewBuilder private var listView: some View {
        HStack(spacing: 10) {
            Image(systemName: "scope").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.accent)
            field("Start a task…", $query) { expanded ? pick() : expand() }
        }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .card(radius: 18)
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded(expand))
            .onKeyPress(.downArrow) { expanded ? move(1) : expand(); return .handled }
            .onKeyPress(.upArrow) { move(-1); return .handled }
            .onChange(of: query) { index = 0; if !query.isEmpty { expand() } }
            .onChange(of: matches.count) { index = min(index, matches.count + lead) }

        if expanded {
            if let s = suggested {
                sectionLabel("Suggested from Calendar", "calendar")
                row(s.template.map { AnyView(emojiTile($0.emoji)) } ?? AnyView(calendarTile), s.title,
                    note: [s.template?.name, s.time].compactMap { $0 }.joined(separator: " · "), selected: index == 0)
                    .onHover { if $0, dragging == nil { index = 0 } }
                    .onTapGesture { chooseSuggestion(s) }
                    .padding(.horizontal, 6)
                    .modifier(BlurFade(hidden: !revealed))
                    .animation(revealAnimation(0), value: revealed)
                sectionLabel("Templates", "square.stack")
            }
            // Long lists scroll inside the card instead of running past the bottom of the panel.
            let rows = matches.count + 1, overflows = rows > maxRows
            ScrollViewReader { proxy in
            ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(matches.enumerated()), id: \.element.id) { i, t in
                    row(emojiTile(t.emoji), t.name, note: t.lastStopNote, selected: i + lead == index && dragging == nil)
                        .onHover { if $0, dragging == nil { index = i + lead } } // instant: frequent, pointer-driven
                        .onTapGesture { choose(t) }
                        .contextMenu {
                            Button("Edit", systemImage: "pencil") { choose(t) }
                            Button("Delete", systemImage: "trash", role: .destructive) { store.deleteTemplate(t.id) }
                        }
                        // Reorder only the full list: positions in a filtered list are ambiguous.
                        .modifier(ReorderDrag(id: t.id, step: 40, items: $store.templates, dragging: $dragging,
                                              enabled: query.isEmpty))
                        .modifier(BlurFade(hidden: !revealed))
                        .animation(revealAnimation(i), value: revealed)
                }
                // Always last: a new template, named after the search if there is one.
                row(newTile, query.isEmpty ? "New Template" : "New Template “\(query)”",
                    note: store.templates.isEmpty ? "No templates yet" : "", selected: index == matches.count + lead)
                    .onHover { if $0 { index = matches.count + lead } }
                    .onTapGesture(perform: createTemplate)
                    .modifier(BlurFade(hidden: !revealed))
                    .animation(revealAnimation(matches.count), value: revealed)
                    .id(Self.newRowID)
            }
            .padding(.horizontal, 6).padding(.vertical, suggested == nil ? 6 : 2) // rows sit on the glass; highlight is a frosted chip
            }
            .scrollIndicators(.never)
            .frame(height: CGFloat(min(rows, maxRows)) * 40 + 10)
            // Soft edge where rows scroll out of view, like the app chooser.
            .mask(LinearGradient(stops: [.init(color: .black, location: overflows ? 0.88 : 1), .init(color: overflows ? .clear : .black, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
            .onChange(of: keyboardTarget) { if let t = keyboardTarget { proxy.scrollTo(t) } } // arrow keys keep the selection in view
            }

            hint("↑↓ choose · ↩ select · esc close")
                .padding(.horizontal, 14).padding(.top, 2).padding(.bottom, 6)
                .modifier(BlurFade(hidden: !revealed))
                .animation(revealAnimation(matches.count + 1), value: revealed)
                .onAppear { revealed = true }
        }
    }

    private func row(_ tile: some View, _ title: String, note: String, selected: Bool) -> some View {
        HStack(spacing: 10) {
            tile
            Text(title).font(.system(size: 14, weight: .medium)).lineLimit(1)
            Spacer(minLength: 12)
            if !note.isEmpty {
                Text(note).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 38)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.onGlass)
                    .matchedGeometryEffect(id: "selection", in: ns)
            }
        }
        .contentShape(Rectangle())
    }

    // MARK: Goal

    /// Start screen. The template itself is editable here: icon, name, and apps.
    private func goalView(_ i: Int) -> some View {
        let t = store.templates[i]
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button { toggle(.icon) } label: {
                    Text(t.emoji).font(.system(size: 18))
                        .frame(width: 34, height: 34)
                        .background(editing == .icon ? Theme.card : Theme.onGlass,
                                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).help("Choose an icon")
                TextField("", text: $store.templates[i].name, prompt: Text("Template name"))
                    .textFieldStyle(.plain).font(.system(size: 15, weight: .semibold))
                Button { toggle(.apps) } label: { AppStrip(apps: t.apps, active: editing == .apps) }
                    .buttonStyle(.plain).help("Choose the apps for this task")
            }
            .padding(.horizontal, 8).padding(.top, 6)
            if editing == .icon {
                EmojiGrid(emoji: $store.templates[i].emoji) { toggle(nil) }
                    .padding(.horizontal, 4)
                    .transition(.reveal(reduceMotion: reduceMotion))
            }
            if editing == .apps {
                AppChooser(apps: $store.templates[i].apps, listHeight: 200)
                    .transition(.reveal(reduceMotion: reduceMotion))
            }
            // The composer: an opaque cloud on the glass, like the references' message box.
            VStack(alignment: .leading, spacing: 10) {
                if !t.lastStopNote.isEmpty {
                    Text("Last time: \(t.lastStopNote)").font(.callout).foregroundStyle(Theme.note)
                        .fixedSize(horizontal: false, vertical: true)
                }
                field("What will you finish? (optional)", $goal) { start(t) }
                HStack {
                    hint("↩ start · esc close")
                    Spacer()
                    Button { start(t) } label: {
                        Image(systemName: "arrow.up").font(.system(size: 13, weight: .bold))
                    }
                    .buttonStyle(RoundButtonStyle())
                    .help("Start")
                }
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 10)
            .card(radius: 18)
        }
        .transition(.reveal(reduceMotion: reduceMotion))
    }

    // MARK: Finish

    private func finishView(_ s: Session) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                emojiTile(s.template.emoji)
                // Plain primary: .secondary turns near-invisible on the frosted shell over bright windows.
                Text("\(s.template.name) · \(store.elapsed(s))")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary)
            }
            .padding(.horizontal, 8).padding(.top, 6)
            VStack(alignment: .leading, spacing: 10) {
                if s.goal != s.template.name { // no goal typed: the header already names the task
                    Text(s.goal).font(.system(size: 18, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                }
                field("Where did you stop?", $note, onSubmit: finish)
                HStack(spacing: 8) {
                    hint("esc close")
                    Spacer()
                    Button("Switch Task…") { withAnimation(Theme.settle) { switching = true } }
                        .buttonStyle(PillButtonStyle())
                    Button("Finish", action: finish).buttonStyle(PillButtonStyle(prominent: true))
                }
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 10)
            .card(radius: 18)
        }
    }

    // MARK: Actions

    private func expand() {
        guard !expanded else { return }
        withAnimation(morph) { expanded = true }
    }

    private func move(_ d: Int) {
        index = min(max(index + d, 0), matches.count + lead) // instant: keyboard-driven; last row is "New Template"
        let j = max(index - lead, 0)
        keyboardTarget = matches.indices.contains(j) ? AnyHashable(matches[j].id) : AnyHashable(Self.newRowID)
    }

    private func pick() {
        if let s = suggested, index == 0 { return chooseSuggestion(s) }
        matches.indices.contains(index - lead) ? choose(matches[index - lead]) : createTemplate()
    }

    /// Opens the matching template (or a new one named after the event) with the event as the goal.
    private func chooseSuggestion(_ s: CalendarSuggestion) {
        goal = s.title
        if let t = s.template.flatMap({ m in store.templates.first { $0.id == m.id } }) {
            choose(t)
        } else {
            let t = Template(name: s.title)
            store.addTemplate(t)
            withAnimation(settle) { chosenID = t.id; editing = .apps }
        }
    }

    private func choose(_ t: Template) {
        withAnimation(settle) { chosenID = t.id }
    }

    /// New template opens straight into its app list, where "Use Current Setup" is one click.
    private func createTemplate() {
        let t = Template(name: query.isEmpty ? "New task" : query)
        store.addTemplate(t)
        withAnimation(settle) { chosenID = t.id; editing = .apps }
    }

    private func toggle(_ e: Editing?) {
        withAnimation(settle) { editing = editing == e ? nil : e }
    }

    private func finish() {
        store.finish(note: note)
        close()
    }

    private func start(_ t: Template) {
        let g = goal.trimmingCharacters(in: .whitespaces)
        close()
        store.start(t, goal: g.isEmpty ? t.name : g) // goal is optional: ↩ on an empty field quick-starts
    }

    // MARK: Pieces

    /// Rows fade up one after another (30 ms apart, capped) when the list first opens.
    private func revealAnimation(_ i: Int) -> Animation {
        reduceMotion ? .easeOut(duration: 0.15) : Theme.reveal.delay(Double(min(i, 6)) * 0.03 + 0.05)
    }

    private func field(_ prompt: String, _ text: Binding<String>, onSubmit: @escaping () -> Void) -> some View {
        TextField("", text: text, prompt: Text(prompt).foregroundStyle(Theme.muted))
            .textFieldStyle(.plain)
            .font(.system(size: 15, weight: .medium))
            .focused($focused)
            .onSubmit(onSubmit)
            .onAppear { DispatchQueue.main.async { focused = true } }
    }

    private func emojiTile(_ emoji: String) -> some View {
        Text(emoji).font(.system(size: 14))
            .frame(width: 26, height: 26)
            .background(Theme.onGlass, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private var calendarTile: some View {
        Image(systemName: "calendar").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accent)
            .frame(width: 26, height: 26)
            .background(Theme.onGlass, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func sectionLabel(_ title: String, _ icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).frame(width: 14) // same width for every icon, so the titles line up
            Text(title)
        }
            .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted)
            .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 2)
            .modifier(BlurFade(hidden: !revealed))
            .animation(revealAnimation(0), value: revealed)
    }

    private var newTile: some View {
        Image(systemName: "plus").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            .frame(width: 26, height: 26)
            .background(Theme.onGlass, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func hint(_ s: String) -> some View {
        Text(s).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.muted)
    }
}

/// The reference's round send button.
struct RoundButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(enabled ? AnyShapeStyle(.white) : AnyShapeStyle(.tertiary))
            .frame(width: 30, height: 30)
            .background(enabled ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.selected), in: Circle())
            .contentShape(Circle())
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(Theme.quick, value: configuration.isPressed)
            .animation(Theme.quick, value: enabled)
    }
}
