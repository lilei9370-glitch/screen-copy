import AppKit

@MainActor
final class PermissionGuide: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var onGranted: (() -> Void)?
    private let status = NSTextField(wrappingLabelWithString: "")

    func show(onGranted: @escaping () -> Void) {
        self.onGranted = onGranted
        if CGPreflightScreenCaptureAccess() {
            finish()
            return
        }
        if window == nil {
            let heading = NSTextField(labelWithString: "允许「框选取字」读取屏幕")
            heading.font = .systemFont(ofSize: 19, weight: .semibold)
            let steps = NSTextField(wrappingLabelWithString: """
            1. 打开系统设置中的“隐私与安全性” → “录屏与系统录音”，开启「框选取字」。

            2. 列表里找不到时，点“＋”，按 ⌘⇧G，粘贴下方路径，按回车后点“打开”。

            3. 如果列表中已有失效的旧版「框选取字」，选中旧条目点“−”移除，再用上面的方式添加当前 App。
            """)
            let path = NSTextField(wrappingLabelWithString: Bundle.main.bundleURL.path)
            path.isSelectable = true
            path.lineBreakMode = .byCharWrapping
            path.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            let location = NSStackView(views: [
                NSButton(title: "在访达中显示此 App", target: self, action: #selector(reveal)),
                NSButton(title: "复制 App 路径", target: self, action: #selector(copyPath))
            ])
            let open = NSButton(title: "打开权限设置", target: self, action: #selector(openSettings))
            open.keyEquivalent = "\r"
            let actions = NSStackView(views: [
                open, NSButton(title: "我已开启，重新检查", target: self, action: #selector(check))
            ])
            status.textColor = .secondaryLabelColor
            status.isHidden = true

            let stack = NSStackView(views: [heading, steps, path, location, actions, status])
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 15
            stack.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 22, right: 24)
            stack.widthAnchor.constraint(equalToConstant: 484).isActive = true
            for field in [steps, path, status] {
                field.widthAnchor.constraint(equalToConstant: 436).isActive = true
            }
            let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "框选取字 · 屏幕录制权限"
            window.delegate = self
            window.isReleasedWhenClosed = false
            window.contentView = stack
            window.setContentSize(stack.fittingSize)
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func openSettings() {
        if CGRequestScreenCaptureAccess() {
            finish()
        } else {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
    }

    @objc private func reveal() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    @objc private func copyPath() {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(Bundle.main.bundleURL.path, forType: .string)
    }

    @objc private func check() {
        if CGPreflightScreenCaptureAccess() {
            finish()
        } else {
            status.stringValue = "仍未检测到权限。请确认已开启当前 App 的开关。如果系统提示退出并重新打开，请按提示操作。"
            status.isHidden = false
            if let stack = window?.contentView as? NSStackView {
                window?.setContentSize(stack.fittingSize)
            }
        }
    }

    private func finish() {
        let callback = onGranted
        onGranted = nil
        window?.close()
        callback?()
    }

    func windowWillClose(_ notification: Notification) {
        onGranted = nil
        window = nil
    }
}
