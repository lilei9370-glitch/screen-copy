import AppKit

@main
enum ColdCaptureShortcut {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let bundle = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let shortcut = AppShortcut {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            NSWorkspace.shared.open([AppShortcut.captureURL], withApplicationAt: bundle, configuration: configuration) { _, error in
                if let error { NSLog("无法打开框选取字：%@", error.localizedDescription) }
            }
        }
        let observer = DistributedNotificationCenter.default().addObserver(
            forName: AppShortcut.changed, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { shortcut.refresh() }
        }
        withExtendedLifetime((observer, shortcut)) { app.run() }
    }
}
