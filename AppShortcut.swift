import AppKit
import Carbon.HIToolbox

@MainActor
final class AppShortcut {
    private struct Shortcut: Equatable {
        let key: UInt32
        let modifiers: UInt32
        let title: String

        static let standard = Shortcut(key: UInt32(kVK_ANSI_D), modifiers: UInt32(controlKey | shiftKey | cmdKey), title: "⌃⇧⌘D")
    }

    static let bundleID = "io.github.lilei9370-glitch.screencopy"
    static let captureURL = URL(string: "leizi-screen-copy://capture")!
    static let changed = Notification.Name(bundleID + ".shortcutChanged")

    private let preference = "captureShortcut" as CFString
    private let ownsShortcut: () -> Bool
    private let onPress: () -> Void
    private var binding: (shortcut: Shortcut, ref: EventHotKeyRef)?
    private var shortcut = Shortcut.standard
    private var isChoosing = false

    var title: String { shortcut.title }
    var isRegistered: Bool { binding != nil }

    init(ownsShortcut: @escaping () -> Bool = { true }, onPress: @escaping () -> Void) {
        self.ownsShortcut = ownsShortcut
        self.onPress = onPress
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let controller = Unmanaged<AppShortcut>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated {
                if !controller.isChoosing { controller.onPress() }
            }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), nil)
        refresh()
    }

    func refresh() {
        let domain = Self.bundleID as CFString
        CFPreferencesAppSynchronize(domain)
        if let saved = CFPreferencesCopyAppValue(preference, domain) as? [String: Any],
           let key = saved["key"] as? UInt32, let modifiers = saved["modifiers"] as? UInt32,
           let title = saved["title"] as? String {
            shortcut = Shortcut(key: key, modifiers: modifiers, title: title)
        } else {
            shortcut = .standard
        }
        if !ownsShortcut() {
            release()
        } else if binding?.shortcut != shortcut {
            let reference = register(shortcut)
            release()
            if let reference { binding = (shortcut, reference) }
        }
    }

    func release() {
        if let binding { UnregisterEventHotKey(binding.ref) }
        binding = nil
    }

    static func announceChange() {
        DistributedNotificationCenter.default().postNotificationName(changed, object: nil, userInfo: nil, deliverImmediately: true)
    }

    func choose() {
        isChoosing = true
        defer { isChoosing = false }
        let dialog = NSAlert()
        dialog.messageText = "设置软件快捷键"
        dialog.informativeText = "请按下新的组合键，至少包含 Command、Option 或 Control。启用关闭后唤起时也使用这组按键。"
        let confirm = dialog.addButton(withTitle: "保存")
        dialog.addButton(withTitle: "取消").keyEquivalent = "\u{1b}"
        dialog.addButton(withTitle: "恢复默认 \(Shortcut.standard.title)")
        let label = NSTextField(labelWithString: shortcut.title)
        label.frame = CGRect(x: 0, y: 0, width: 220, height: 28)
        label.font = .monospacedSystemFont(ofSize: 16, weight: .medium)
        dialog.accessoryView = label
        confirm.isEnabled = false

        var chosen: Shortcut?
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode != kVK_Escape else { return event }
            let flags = event.modifierFlags
            let available: [(NSEvent.ModifierFlags, Int, String)] = [
                (.control, controlKey, "⌃"), (.option, optionKey, "⌥"),
                (.shift, shiftKey, "⇧"), (.command, cmdKey, "⌘")
            ]
            guard !flags.intersection([.command, .option, .control]).isEmpty else { return event }
            let active = available.filter { flags.contains($0.0) }
            let character = event.charactersIgnoringModifiers?.uppercased() ?? ""
            guard !character.isEmpty, character.unicodeScalars.allSatisfy({
                !CharacterSet.controlCharacters.contains($0) && !(0xF700...0xF8FF).contains($0.value)
            }) else { return nil }
            let title = active.map { $0.2 }.joined() + character
            chosen = Shortcut(key: UInt32(event.keyCode), modifiers: UInt32(active.reduce(0) { $0 | $1.1 }), title: title)
            label.stringValue = title
            confirm.isEnabled = true
            return nil
        }
        NSApp.activate()
        let response = dialog.runModal()
        if let monitor { NSEvent.removeMonitor(monitor) }
        if response == .alertThirdButtonReturn { chosen = .standard }
        guard response == .alertFirstButtonReturn || response == .alertThirdButtonReturn, let chosen else { return }
        if chosen == shortcut && (isRegistered || !ownsShortcut()) { return }
        guard let reference = register(chosen) else {
            let conflict = NSAlert()
            conflict.messageText = "这组快捷键已被占用"
            conflict.informativeText = "请试试其他组合键。"
            conflict.runModal()
            return
        }
        release()
        shortcut = chosen
        if ownsShortcut() {
            binding = (chosen, reference)
        } else {
            UnregisterEventHotKey(reference)
        }
        let domain = Self.bundleID as CFString
        CFPreferencesSetAppValue(preference, ["key": chosen.key, "modifiers": chosen.modifiers, "title": chosen.title] as CFDictionary, domain)
        CFPreferencesAppSynchronize(domain)
        Self.announceChange()
    }

    private func register(_ shortcut: Shortcut) -> EventHotKeyRef? {
        var reference: EventHotKeyRef?
        let id = EventHotKeyID(signature: 0x53434F50, id: 1) // SCOP
        let status = RegisterEventHotKey(shortcut.key, shortcut.modifiers, id, GetApplicationEventTarget(),
                                         OptionBits(kEventHotKeyExclusive), &reference)
        return status == noErr ? reference : nil
    }
}
