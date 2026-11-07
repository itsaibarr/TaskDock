import SwiftUI

@main
struct TaskDockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @ObservedObject var store = Store.shared

    var body: some Scene {
        MenuBarExtra {
            MenuView().environmentObject(store)
        } label: {
            if let s = store.session {
                Text("\(s.template.emoji) \(String(s.goal.prefix(24))) · \(store.elapsed(s))")
            } else {
                Image(systemName: "scope")
            }
        }
        .menuBarExtraStyle(.window)

        Window("Templates", id: "templates") {
            EditorView().environmentObject(store)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 760, height: 580)
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(Debug.enabled ? .presented : .suppressed)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            Store.shared.boot()
            Hotkey.register { MainActor.assumeIsolated { Windows.togglePicker() } }
            Debug.run()
            E2E.run()
        }
    }
}

struct MenuView: View {
    @EnvironmentObject var store: Store
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var calendar = CalendarFeed.shared
    @State private var note = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            statusCard

            VStack(spacing: 0) {
                if store.session == nil {
                    row("Start a Task…", "play.circle", shortcut: "⌃⌥Space") { Windows.togglePicker() }
                }
                row("New Template from Current Setup", "plus.square.on.square") {
                    store.addTemplate(store.captureTemplate())
                    showEditor()
                }
                row("Edit Templates…", "square.stack", action: showEditor)
                if !calendar.connected {
                    row("Connect Calendars…", "calendar", action: calendar.connect)
                        .help("Suggests a task from the event happening now. Google calendars: add your account in System Settings › Internet Accounts.")
                }
                row("Quit TaskDock", "power", shortcut: "⌘Q") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }

            HStack(spacing: 6) {
                Circle().fill(store.browsers > 0 && !store.outdatedExtension ? Color.green : Color.orange).frame(width: 6, height: 6)
                Text(store.outdatedExtension ? "Reload the TaskDock extension in your browser"
                     : store.browsers > 0 ? "Browser connected" : "Browser extension not connected")
                if calendar.connected {
                    Circle().fill(Color.green).frame(width: 6, height: 6).padding(.leading, 6)
                    Text("Calendars connected")
                }
            }
            .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            .padding(.horizontal, 10).padding(.bottom, 2)
        }
        .padding(8)
        .frame(width: 300, alignment: .leading)
    }

    @ViewBuilder private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let s = store.session {
                HStack(spacing: 6) {
                    Text(s.template.emoji)
                    Text("\(s.template.name) · \(store.elapsed(s))").foregroundStyle(.secondary)
                }
                .font(.system(size: 12, weight: .medium))
                if s.goal != s.template.name {
                    Text(s.goal).font(.system(size: 15, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                }
                TextField("Where did you stop? What's next?", text: $note)
                    .textFieldStyle(FilledFieldStyle())
                    .onSubmit(finish)
                HStack(spacing: 8) {
                    Spacer()
                    Button("Switch Task…") { Windows.togglePicker(switching: true) }
                        .buttonStyle(PillButtonStyle())
                    Button("Finish", action: finish)
                        .buttonStyle(PillButtonStyle(prominent: true))
                        .keyboardShortcut(.defaultAction)
                }
            } else {
                Text("No active task").font(.system(size: 15, weight: .semibold))
                Text("Press ⌃⌥Space to pick a template and set a goal.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(radius: 12)
    }

    private func row(_ title: String, _ icon: String, shortcut: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).frame(width: 16).foregroundStyle(.secondary)
                Text(title)
                Spacer()
                if let shortcut { Text(shortcut).foregroundStyle(.secondary) }
            }
            .font(.system(size: 13))
        }
        .buttonStyle(RowButtonStyle())
    }

    private func showEditor() {
        openWindow(id: "templates")
        NSApp.activate()
    }

    private func finish() {
        store.finish(note: note)
        note = ""
    }
}
