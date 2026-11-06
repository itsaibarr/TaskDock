import Carbon

/// Global hotkey ⌃⌥Space via Carbon (still the only API that needs no Accessibility permission).
enum Hotkey {
    static var action: () -> Void = {}
    private static var ref: EventHotKeyRef?

    static func register(_ action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { Hotkey.action() }
            return noErr
        }, 1, &spec, nil, nil)
        let id = EventHotKeyID(signature: OSType(0x5444_4B31), id: 1) // "TDK1"
        let status = RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &ref)
        if status != noErr { NSLog("TaskDock: hotkey ⌃⌥Space is taken (\(status))") }
    }
}
