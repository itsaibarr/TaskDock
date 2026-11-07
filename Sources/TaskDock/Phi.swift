import AppKit
import ApplicationServices

/// Phi browser: each task can have its own Phi Space, which keeps that task's tabs.
/// Uses Phi's AppleScript commands (`list spaces`, `activate space`), which answer in JSON.
enum Phi {
    static let id = "com.phibrowser.Mac"

    struct Space: Decodable, Hashable, Identifiable {
        let id: String
        let title: String
    }

    /// Phi's Spaces, or none while Phi isn't running (asking would launch it). Blocking.
    static func spaces() -> [Space] {
        #if DEBUG
        if Debug.enabled { return [Space(id: "a", title: "Default"), Space(id: "b", title: "Writing")] }
        #endif
        struct Reply: Decodable { let spaces: [Space] }
        guard Snapshot.isRunning(id), let data = osascript("tell application id \"\(id)\" to list spaces") else { return [] }
        return (try? JSONDecoder().decode(Reply.self, from: data))?.spaces ?? []
    }

    /// The template's Space: the one it names, otherwise (also if that one was renamed or deleted) the one titled like the template.
    static func space(for t: Template, in spaces: [Space]) -> Space? {
        named(t.phiSpace ?? t.name, in: spaces) ?? named(t.name, in: spaces)
    }

    static func named(_ title: String, in spaces: [Space]) -> Space? {
        let title = title.trimmingCharacters(in: .whitespaces)
        return spaces.first { $0.title.trimmingCharacters(in: .whitespaces).localizedCaseInsensitiveCompare(title) == .orderedSame }
    }

    /// Switches Phi to the template's Space once Phi is running (waits up to 10 s for a launch).
    /// A Space that doesn't exist yet is created first, named like the template. Blocking.
    static func activate(for t: Template) {
        var all: [Space] = []
        for _ in 0..<20 { // a Phi that's just launching answers with no Spaces for a moment
            all = spaces()
            if !all.isEmpty { break }
            Thread.sleep(forTimeInterval: 0.5)
        }
        guard !all.isEmpty else { return } // never create while Phi can't tell us what exists
        if space(for: t, in: all) == nil, create(t.name, prompt: false) {
            all = spaces()
            DispatchQueue.main.async { Store.shared.linkPhiSpace(t.id, t.name) } // renaming the template later keeps the link
        }
        guard let space = space(for: t, in: all) else { return }
        let escaped = space.id.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        _ = osascript("tell application id \"\(id)\" to activate space space id \"\(escaped)\"")
    }

    // MARK: Creating a Space

    /// Phi's scripting can't create Spaces, so this uses its menu, like a person would:
    /// "New Space" → type the name → Return. Needs Accessibility; `prompt` asks for it (only from a click,
    /// never in the middle of starting a task). Blocking; true once Phi lists the Space.
    @discardableResult
    static func create(_ name: String, prompt: Bool) -> Bool {
        lock.lock() // one at a time: two creates would interleave keystrokes
        defer { lock.unlock() }
        if named(name, in: spaces()) != nil { return true } // made meanwhile (or by hand)
        guard AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": prompt] as CFDictionary),
              let phi = Snapshot.running(id).first else {
            NSLog("TaskDock: can't create Phi Space \"\(name)\": Accessibility not allowed or Phi not running")
            return false
        }
        let app = AXUIElementCreateApplication(phi.processIdentifier)
        guard let item = menuItems(app).first(where: { isNewSpace($0.title) }) else {
            NSLog("TaskDock: no New Space item in Phi's menus. Items: \(menuItems(app).map(\.title).joined(separator: " | "))")
            return false
        }
        phi.activate()
        Thread.sleep(forTimeInterval: 0.3)
        let before = attribute(app, kAXFocusedUIElementAttribute)
        AXUIElementPerformAction(item.element, kAXPressAction as CFString)
        // Type only into the field the New Space form just focused: a text field that wasn't focused
        // before the click. A page's text box or the address bar never qualifies, so nothing of yours is overwritten.
        var field = false
        for _ in 0..<10 where !field { // the form animates in and focuses its name field
            Thread.sleep(forTimeInterval: 0.2)
            let now = attribute(app, kAXFocusedUIElementAttribute)
            let moved = now != nil && (before == nil || !CFEqual(before, now))
            // The name field starts empty; the address bar never does.
            field = moved && [kAXTextFieldRole, kAXTextAreaRole].contains(role(now))
                && ((now.flatMap { attribute($0 as! AXUIElement, kAXValueAttribute) } as? String) ?? "").isEmpty
        }
        NSLog("TaskDock: pressed Phi \"\(item.title)\"; focused: \(describe(attribute(app, kAXFocusedUIElementAttribute)))")
        guard field else { return false }
        type(name, to: phi.processIdentifier)
        for _ in 0..<10 {
            Thread.sleep(forTimeInterval: 0.3)
            if named(name, in: spaces()) != nil { return true }
        }
        NSLog("TaskDock: Phi Space \"\(name)\" didn't appear after creating it")
        return false
    }

    /// "New Space", "New Space…", "Create a New Space"; not the incognito one.
    static func isNewSpace(_ title: String) -> Bool {
        let t = title.lowercased()
        return (t.hasPrefix("new") || t.hasPrefix("create")) && t.contains("space") && !t.contains("incognito")
    }

    /// Every item in the app's menu bar, depth first.
    private static func menuItems(_ app: AXUIElement) -> [(title: String, element: AXUIElement)] {
        func walk(_ e: AXUIElement) -> [(title: String, element: AXUIElement)] {
            let title = attribute(e, kAXTitleAttribute) as? String ?? ""
            let role = attribute(e, kAXRoleAttribute) as? String
            let me = role == kAXMenuItemRole && !title.isEmpty ? [(title, e)] : []
            let kids = attribute(e, kAXChildrenAttribute) as? [AXUIElement] ?? []
            return me + kids.flatMap(walk)
        }
        guard let bar = attribute(app, kAXMenuBarAttribute) else { return [] }
        return walk(bar as! AXUIElement)
    }

    /// Types `text` into the focused (new, empty) field and presses Return.
    private static func type(_ text: String, to pid: pid_t) {
        func key(_ code: CGKeyCode, unicode: String? = nil) {
            for down in [true, false] {
                guard let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down) else { continue }
                if let unicode { e.keyboardSetUnicodeString(stringLength: unicode.utf16.count, unicodeString: Array(unicode.utf16)) }
                e.postToPid(pid)
            }
            Thread.sleep(forTimeInterval: 0.03)
        }
        for ch in text { key(0, unicode: String(ch)) }
        Thread.sleep(forTimeInterval: 0.2)
        key(36) // Return
    }

    private static func attribute(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
    }

    private static let lock = NSLock()

    private static func role(_ v: CFTypeRef?) -> String? {
        guard let v, CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return attribute(v as! AXUIElement, kAXRoleAttribute) as? String
    }

    private static func describe(_ v: CFTypeRef?) -> String {
        guard let v, CFGetTypeID(v) == AXUIElementGetTypeID() else { return "nothing" }
        let e = v as! AXUIElement
        return [kAXRoleAttribute, kAXDescriptionAttribute, kAXPlaceholderValueAttribute]
            .compactMap { attribute(e, $0) as? String }.joined(separator: ", ")
    }
}
