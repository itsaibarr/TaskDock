import SwiftUI

/// Small grid of icons for a template. Shared by the picker and the Templates window.
struct EmojiGrid: View {
    @Binding var emoji: String
    var onPick: () -> Void = {}

    static let options = [
        "🎯", "✍️", "💻", "📚", "📝", "📖", "🧠", "💡",
        "🎨", "📷", "🎬", "🎧", "🎙️", "🎵", "🎸", "🎮",
        "📊", "📈", "💼", "💰", "🧾", "📅", "📧", "💬",
        "🛠️", "⚙️", "🐞", "🔬", "🧪", "🔍", "🚀", "🧩",
        "🏋️", "🧘", "🍳", "☕️", "🌱", "🏠", "✈️", "🌙",
    ]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 36), spacing: 4), count: 8), spacing: 4) {
            ForEach(Self.options, id: \.self) { e in
                Button { emoji = e; onPick() } label: {
                    Text(e).font(.system(size: 20)).frame(maxWidth: .infinity).frame(height: 36)
                }
                .buttonStyle(TileButtonStyle(selected: e == emoji))
            }
        }
    }
}

/// Installed apps, found once per launch: the usual app folders plus anything running.
@MainActor
enum AppCatalog {
    static let all: [AppRef] = {
        let fm = FileManager.default
        let roots = ["/Applications", "/Applications/Utilities", "/System/Applications",
                     "/System/Applications/Utilities", fm.homeDirectoryForCurrentUser.path + "/Applications"]
        var urls = roots.flatMap { root in
            ((try? fm.contentsOfDirectory(atPath: root)) ?? [])
                .filter { $0.hasSuffix(".app") }
                .map { URL(fileURLWithPath: root).appendingPathComponent($0) }
        }
        urls += NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.compactMap(\.bundleURL)
        var seen: Set<String> = [Bundle.main.bundleIdentifier ?? ""]
        return urls.compactMap(AppRef.init(url:))
            .filter { seen.insert($0.bundleID).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }()
}

/// Searchable list of installed apps with checkmarks, plus a one-click "use what's open now".
struct AppChooser: View {
    @Binding var apps: [AppRef]
    var listHeight: CGFloat = 240
    @State private var query = ""
    /// Apps already chosen when the list opened go first. Fixed on open, so rows don't jump while toggling.
    @State private var pinned: Set<String> = []

    private var shown: [AppRef] {
        let all = AppCatalog.all.filter { pinned.contains($0.id) } + AppCatalog.all.filter { !pinned.contains($0.id) }
        return query.isEmpty ? all : all.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("", text: $query, prompt: Text("Search apps").foregroundStyle(Theme.muted))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10).frame(height: 30)
                    .card(radius: 10)
                Button("Use Current Setup") { apps = Store.shared.currentApps() }
                    .buttonStyle(PillButtonStyle())
                    .help("Replace the list with the apps open right now")
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(shown) { app in
                        let on = apps.contains { $0.id == app.id }
                        Button { toggle(app) } label: {
                            HStack(spacing: 10) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                                    .resizable().frame(width: 20, height: 20)
                                Text(app.name).lineLimit(1)
                                Spacer()
                                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(on ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.tertiary))
                            }
                            .font(.system(size: 13))
                        }
                        .buttonStyle(RowButtonStyle())
                    }
                }
            }
            .frame(height: listHeight)
            // Soft bottom edge instead of a hard cut where the list scrolls.
            .mask(LinearGradient(stops: [.init(color: .black, location: 0.85), .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
        }
        .onAppear { pinned = Set(apps.map(\.id)) }
        .onChange(of: apps) { if query.isEmpty, pinned.isEmpty { pinned = Set(apps.map(\.id)) } } // after Use Current Setup
    }

    private func toggle(_ app: AppRef) {
        if let i = apps.firstIndex(where: { $0.id == app.id }) { apps.remove(at: i) } else { apps.append(app) }
    }
}

/// Overlapping icons of a template's apps, used as the button that opens the chooser.
struct AppStrip: View {
    let apps: [AppRef]
    var active = false

    var body: some View {
        HStack(spacing: 6) {
            if apps.isEmpty {
                Text("Choose apps").font(.system(size: 12, weight: .medium))
            } else {
                HStack(spacing: -5) {
                    ForEach(apps.prefix(5)) { app in
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)).resizable().frame(width: 20, height: 20)
                    }
                }
                if apps.count > 5 { Text("+\(apps.count - 5)").font(.system(size: 12, weight: .medium)) }
            }
            Image(systemName: active ? "chevron.up" : "chevron.down").font(.system(size: 9, weight: .bold))
                .contentTransition(.symbolEffect(.replace))
        }
        .foregroundStyle(.primary.opacity(0.75)) // .secondary fades out on the frosted shell
        .padding(.horizontal, 8).frame(height: 28)
        .background(active ? Theme.card : Theme.onGlass, in: Capsule())
        .contentShape(Capsule())
    }
}

/// Square cell with a grey hover and selected fill.
struct TileButtonStyle: ButtonStyle {
    var selected = false
    func makeBody(configuration: Configuration) -> some View { Tile(configuration: configuration, selected: selected) }

    private struct Tile: View {
        let configuration: Configuration
        let selected: Bool
        @State private var hovering = false

        var body: some View {
            configuration.label
                .background(selected || configuration.isPressed ? Theme.selected : hovering ? Theme.hover : .clear,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}

/// Drag a template row up or down to reorder; neighbours slide out of the way as it passes them.
struct ReorderDrag: ViewModifier {
    let id: UUID
    /// Row height plus spacing: how far to drag before swapping with a neighbour.
    let step: CGFloat
    @Binding var items: [Template]
    @Binding var dragging: UUID?
    var enabled = true
    @State private var offset: CGFloat = 0
    @State private var consumed: CGFloat = 0 // distance already turned into swaps

    func body(content: Content) -> some View {
        let active = dragging == id
        content
            .scaleEffect(active ? 1.02 : 1)
            .shadow(color: .black.opacity(active ? 0.14 : 0), radius: 8, y: 4)
            .offset(y: active ? offset : 0)
            .zIndex(active ? 1 : 0)
            // Global space: the row itself moves on every swap, so local translation would drift.
            .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .global).onChanged(changed).onEnded { _ in ended() },
                     including: enabled ? .all : .subviews)
    }

    private func changed(_ v: DragGesture.Value) {
        dragging = id
        let steps = Int(((v.translation.height - consumed) / step).rounded())
        if steps != 0, let from = items.firstIndex(where: { $0.id == id }) {
            let to = min(max(from + steps, 0), items.count - 1)
            if to != from {
                withAnimation(Theme.quick) { items.move(fromOffsets: [from], toOffset: to > from ? to + 1 : to) }
                consumed += CGFloat(to - from) * step
            }
        }
        offset = v.translation.height - consumed
    }

    private func ended() {
        withAnimation(Theme.settle) { offset = 0; dragging = nil }
        consumed = 0
    }
}
