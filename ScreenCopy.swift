import AppKit
import ServiceManagement

@main
enum ScreenCopyApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let tool = CaptureTool()
        app.delegate = tool
        withExtendedLifetime(tool) { app.run() }
    }
}

@MainActor
final class CaptureTool: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private lazy var permissionGuide = PermissionGuide()
    private lazy var launcher = SMAppService.agent(plistName: AppShortcut.bundleID + ".shortcut.plist")
    private lazy var appShortcut = AppShortcut(ownsShortcut: { [weak self] in
        self?.launcher.status != .enabled
    }) { [weak self] in self?.capture() }
    private var launcherItem: NSMenuItem?
    private var captureProcess: Process?
    private var notice: NSPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.dropFirst().first == "--capture" {
            Task { await captureAndQuit() }
            return
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "text.viewfinder", accessibilityDescription: "框选取字")
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: "框选屏幕文字", action: #selector(capture), keyEquivalent: "").target = self
        menu.addItem(withTitle: "设置软件快捷键…", action: #selector(editShortcut), keyEquivalent: "").target = self
        let background = menu.addItem(withTitle: "关闭后也能用快捷键", action: #selector(toggleLauncher), keyEquivalent: "")
        background.target = self
        launcherItem = background
        menu.addItem(withTitle: "屏幕录制权限与使用说明…", action: #selector(openPermissions), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出框选取字", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
        syncShortcut()
        if !CGPreflightScreenCaptureAccess() { openPermissions() }
    }

    @objc private func editShortcut() {
        appShortcut.choose()
        syncShortcut()
    }

    func menuWillOpen(_ menu: NSMenu) { syncShortcut() }

    func applicationDidBecomeActive(_ notification: Notification) {
        if statusItem != nil { syncShortcut() }
    }

    private func syncShortcut() {
        appShortcut.refresh()
        let state = launcher.status
        launcherItem?.state = state == .enabled ? .on : state == .requiresApproval ? .mixed : .off
        let title = appShortcut.isRegistered || state == .enabled ? appShortcut.title : "快捷键未注册"
        statusItem?.button?.toolTip = "框选取字 · \(title)"
        statusItem?.menu?.items.first?.title = "框选屏幕文字（\(title)）"
        if state == .enabled { AppShortcut.announceChange() }
    }

    @objc private func toggleLauncher() {
        Task { await changeLauncher() }
    }

    private func changeLauncher() async {
        defer { syncShortcut() }
        do {
            if launcher.status == .enabled || launcher.status == .requiresApproval {
                try await launcher.unregister()
            } else {
                appShortcut.release()
                try launcher.register()
                if launcher.status == .requiresApproval {
                    let alert = NSAlert()
                    alert.messageText = "请在系统设置中允许后台运行"
                    alert.informativeText = "允许「框选取字」在后台运行后，退出 App 时也能用取字快捷键。"
                    alert.addButton(withTitle: "打开系统设置")
                    alert.addButton(withTitle: "稍后")
                    NSApp.activate()
                    if alert.runModal() == .alertFirstButtonReturn { SMAppService.openSystemSettingsLoginItems() }
                }
            }
        } catch {
            let alert = NSAlert(error: error)
            NSApp.activate()
            alert.runModal()
        }
    }

    @objc private func openPermissions() {
        permissionGuide.show { [weak self] in
            guard let self else { return }
            show("可以取字了，按 \(appShortcut.title) 开始", symbol: "checkmark.circle.fill")
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if statusItem != nil { openPermissions() }
        return false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if urls.contains(AppShortcut.captureURL), launcher.status == .enabled { capture() }
    }

    @objc func capture() {
        guard captureProcess?.isRunning != true else { return }
        guard CGPreflightScreenCaptureAccess() else {
            openPermissions()
            return
        }
        let process = Process()
        process.executableURL = Bundle.main.executableURL
        process.arguments = ["--capture"]
        do {
            try process.run()
            captureProcess = process
        } catch {
            show("无法启动取字：" + error.localizedDescription, symbol: "exclamationmark.circle")
        }
    }

    private func captureAndQuit() async {
        defer { NSApp.terminate(nil) }
        let selection = ScreenSelection()
        do {
            guard let image = try await selection.pick() else { return }
            let clipboard = NSPasteboard.general
            let change = clipboard.changeCount
            let text = try await Task.detached(priority: .userInitiated) {
                try TextRecognition.text(in: image)
            }.value
            if text.isEmpty {
                show("选区内没有识别到文字", symbol: "text.magnifyingglass")
            } else if clipboard.changeCount != change {
                show("已保留你刚复制的内容", symbol: "clipboard")
            } else {
                clipboard.clearContents()
                if clipboard.setString(text, forType: .string) {
                    show("已复制", symbol: "checkmark")
                } else {
                    show("无法写入剪贴板，请再试一次", symbol: "exclamationmark.circle")
                }
            }
        } catch {
            show("取字失败：" + error.localizedDescription, symbol: "exclamationmark.circle")
        }
        try? await Task.sleep(for: .seconds(1.1))
    }

    func applicationWillTerminate(_ notification: Notification) {
        if statusItem != nil {
            appShortcut.release()
            if launcher.status == .enabled { AppShortcut.announceChange() }
        }
        if captureProcess?.isRunning == true { captureProcess?.terminate() }
    }

    private func show(_ message: String, symbol: String) {
        notice?.orderOut(nil)
        let view = NoticeView(message: message, symbol: symbol)
        let size = view.frame.size
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = view
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 52))
        }
        notice = panel
        panel.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self, weak panel] in
            panel?.orderOut(nil)
            if self?.notice === panel { self?.notice = nil }
        }
    }
}

@MainActor
final class NoticeView: NSView {
    init(message: String, symbol: String) {
        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 12.5, weight: .medium)
        label.textColor = .white
        label.sizeToFit()

        let height: CGFloat = 28
        label.setFrameOrigin(NSPoint(x: 30, y: ((height - label.frame.height) / 2).rounded()))
        super.init(frame: NSRect(x: 0, y: 0, width: label.frame.maxX + 11, height: height))

        let icon = NSImageView(frame: NSRect(x: 11, y: 7, width: 14, height: 14))
        icon.symbolConfiguration = .init(pointSize: 12, weight: .semibold)
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.contentTintColor = symbol == "checkmark" ? NSColor(srgbRed: 0.49, green: 0.92, blue: 0.74, alpha: 1) : .white
        addSubview(icon)
        addSubview(label)
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let capsule = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                   xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        NSColor(srgbRed: 0.11, green: 0.13, blue: 0.16, alpha: 0.92).setFill()
        capsule.fill()
        NSColor.white.withAlphaComponent(0.2).setStroke()
        capsule.lineWidth = 0.75
        capsule.stroke()
    }
}
