import SwiftUI

/// Dev-only: `TASKDOCK_SHOTS=<dir>` opens the windows, saves screenshots of them, and quits.
/// Pair with `TASKDOCK_DATA_DIR` so it runs on sample data.
enum Debug {
    #if DEBUG
    static let shotDir = ProcessInfo.processInfo.environment["TASKDOCK_SHOTS"]
    #else
    static let shotDir: String? = nil
    #endif
    static var enabled: Bool { shotDir != nil }
    /// Lets the screenshot run drive the picker ("expand", "choose").
    static let pickerStep = Notification.Name("TaskDockPickerStep")

    @MainActor
    static func run() {
        #if DEBUG
        guard let dir = shotDir else { return }
        Task { @MainActor in
            for (name, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
                NSApp.appearance = NSAppearance(named: appearance)
                await pause(1.5)
                let store = Store.shared
                store.editorSelection = store.templates.first?.id
                await pause(1)
                if let w = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("templates") == true }) {
                    shot(w, "\(dir)/editor-top-\(name).png")
                    scroll(w, by: 220); await pause(0.6)
                    shot(w, "\(dir)/editor-scrolled-\(name).png")
                    scroll(w, by: 2000); await pause(0.6)
                    shot(w, "\(dir)/editor-bottom-\(name).png")
                    scroll(w, by: -5000)
                    store.editorSelection = nil; await pause(0.6)
                    shot(w, "\(dir)/editor-empty-\(name).png")
                }
                let wallpaper = backdrop()
                Windows.togglePicker(); await pause(0.6)
                if let p = Windows.picker { shot(p, below: true, "\(dir)/picker-pill-\(name).png") }
                step("expand")
                for i in 1...3 {
                    await pause(0.07)
                    if let p = Windows.picker { shot(p, below: true, "\(dir)/picker-morph\(i)-\(name).png") }
                }
                await pause(0.7)
                if let p = Windows.picker { shot(p, below: true, "\(dir)/picker-list-\(name).png") }
                if let p = Windows.picker { // drag the first row down two places, without touching the real mouse
                    let x = p.frame.width / 2, y = p.frame.height - 101 // centre of the first row
                    mouse(p, .leftMouseDown, x, y)
                    for dy in stride(from: 10.0, through: 90, by: 10) { mouse(p, .leftMouseDragged, x, y - dy); await pause(0.03) }
                    await pause(0.2)
                    shot(p, below: true, "\(dir)/picker-drag-\(name).png")
                    mouse(p, .leftMouseUp, x, y - 90); await pause(0.5)
                    shot(p, below: true, "\(dir)/picker-dropped-\(name).png")
                }
                step("choose"); await pause(0.7)
                if let p = Windows.picker { shot(p, below: true, "\(dir)/picker-goal-\(name).png") }
                step("icon"); await pause(0.7)
                if let p = Windows.picker { shot(p, below: true, "\(dir)/picker-icon-\(name).png") }
                step("apps"); await pause(0.7)
                if let p = Windows.picker { shot(p, below: true, "\(dir)/picker-apps-\(name).png") }
                step("apps") // close it: frames check that nothing collides while the card shrinks
                for i in 1...4 {
                    await pause(0.06)
                    if let p = Windows.picker { shot(p, below: true, "\(dir)/picker-collapse\(i)-\(name).png") }
                }
                Windows.togglePicker()
                await menuShot("\(dir)/menu-idle-\(name).png")
                if let first = store.templates.first {
                    store.session = Session(template: first, goal: "Draft the intro section",
                                            startedAt: Date().addingTimeInterval(-23 * 60), visibleApps: [])
                    Windows.togglePicker(); await pause(0.8)
                    if let p = Windows.picker { shot(p, below: true, "\(dir)/picker-finish-\(name).png") }
                    Windows.togglePicker()
                    await menuShot("\(dir)/menu-task-\(name).png")
                    store.session = nil
                }
                // Over a window of the opposite brightness: the theme must hold from the first frame (no flip).
                wallpaper.contentView = NSHostingView(rootView: Color(white: name == "dark" ? 0.97 : 0.1))
                Windows.togglePicker(); await pause(0.03)
                if let p = Windows.picker { shot(p, below: true, "\(dir)/picker-contrast-first-\(name).png") }
                await pause(0.6)
                if let p = Windows.picker { shot(p, below: true, "\(dir)/picker-contrast-\(name).png") }
                Windows.togglePicker()
                wallpaper.orderOut(nil)
            }
            NSApp.terminate(nil)
        }
        #endif
    }

    #if DEBUG
    private static func pause(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }

    private static func mouse(_ w: NSWindow, _ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat) {
        guard let e = NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: y), modifierFlags: [],
                                         timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber,
                                         context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else { return }
        w.sendEvent(e)
    }

    private static func step(_ s: String) { NotificationCenter.default.post(name: pickerStep, object: s) }

    /// The menu bar popover can't be opened from code, so its view is drawn in a stand-in window.
    @MainActor
    private static func menuShot(_ path: String) async {
        let host = NSHostingView(rootView: MenuView().environmentObject(Store.shared).glass(radius: 16).padding(20))
        let w = NSWindow(contentRect: NSRect(x: 80, y: 200, width: 300, height: 300),
                         styleMask: [.borderless], backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.level = .floating
        w.contentView = host
        w.setContentSize(host.fittingSize)
        w.orderFrontRegardless()
        await pause(0.6)
        shot(w, below: true, path)
        w.orderOut(nil)
    }

    /// Full-screen test wallpaper (sky, cloud, dunes, big text) just under the floating panels.
    @MainActor
    private static func backdrop() -> NSWindow {
        let frame = NSScreen.main?.frame ?? .zero
        let w = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        w.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1) // under the panels
        w.contentView = NSHostingView(rootView: ZStack {
            LinearGradient(colors: [Color(red: 0.32, green: 0.39, blue: 0.44), Color(red: 0.6, green: 0.68, blue: 0.55),
                                    Color(red: 0.34, green: 0.44, blue: 0.34)], startPoint: .top, endPoint: .bottom)
            Ellipse().fill(.white.opacity(0.85)).frame(width: 320, height: 110).blur(radius: 16).offset(x: -140, y: -300)
            Ellipse().fill(Color(red: 0.78, green: 0.85, blue: 0.68)).frame(width: 1100, height: 300).blur(radius: 30).offset(y: 140)
            Text("TaskDock").font(.system(size: 140, weight: .black)).foregroundStyle(.white.opacity(0.3)).offset(y: -120)
        })
        w.orderFrontRegardless()
        return w
    }

    /// Biggest scroll view in the window = the detail form.
    private static func scroll(_ w: NSWindow, by dy: CGFloat) {
        func all(_ v: NSView) -> [NSScrollView] { (v as? NSScrollView).map { [$0] } ?? [] + v.subviews.flatMap(all) }
        guard let sv = all(w.contentView!).max(by: { $0.frame.width < $1.frame.width }) else { return }
        let maxY = max(0, (sv.documentView?.frame.height ?? 0) - sv.contentView.bounds.height)
        let y = min(max(sv.contentView.bounds.origin.y + dy, -sv.contentInsets.top), maxY)
        sv.contentView.scroll(to: NSPoint(x: 0, y: y))
        sv.reflectScrolledClipView(sv.contentView)
    }

    /// Draws one of our own windows, title bar included. Uses the window server when the
    /// screen is unlocked; otherwise AppKit draws the view tree itself (glass looks flatter).
    /// `below` also captures what's under the window (the test wallpaper), so glass is judged on a real backdrop.
    private static func shot(_ w: NSWindow, below: Bool = false, _ path: String) {
        var rep: NSBitmapImageRep?
        typealias Capture = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        if !screenLocked, let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") {
            // Options: IncludingWindow (+ OnScreenBelowWindow). Image: BoundsIgnoreFraming | BestResolution.
            let top = NSScreen.screens.first?.frame.maxY ?? 0
            let rect = below ? CGRect(x: w.frame.minX, y: top - w.frame.maxY, width: w.frame.width, height: w.frame.height) : .null
            let img = unsafeBitCast(sym, to: Capture.self)(rect, below ? (1 << 3 | 1 << 2) : 1 << 3,
                                                           UInt32(w.windowNumber), 1 | 1 << 3)
            rep = img.map { NSBitmapImageRep(cgImage: $0.takeRetainedValue()) }
        }
        if rep == nil, let frame = w.contentView?.superview, let r = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) {
            frame.cacheDisplay(in: frame.bounds, to: r)
            rep = r
        }
        try? rep?.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    private static var screenLocked: Bool {
        (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false
    }
    #endif
}
