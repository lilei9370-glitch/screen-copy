import AppKit
import ScreenCaptureKit

@MainActor
final class ScreenSelection {
    private typealias Region = (screen: NSScreen, rect: CGRect)

    private var panels: [SelectionPanel] = []
    private var result: CheckedContinuation<Region?, Never>?

    func pick() async throws -> CGImage? {
        guard let (screen, rect) = await pickRegion() else { return nil }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let display = content.displays.first(where: { $0.displayID == id.uint32Value }) else {
            throw NSError(domain: "ScreenSelection", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "没有找到可截取的显示器。"])
        }
        let scale = screen.backingScaleFactor
        let pixels = CGRect(x: rect.minX * scale, y: (screen.frame.height - rect.maxY) * scale,
                            width: rect.width * scale, height: rect.height * scale).integral
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.sourceRect = CGRect(x: pixels.minX / scale, y: pixels.minY / scale,
                                   width: pixels.width / scale, height: pixels.height / scale)
        config.width = Int(pixels.width)
        config.height = Int(pixels.height)
        config.showsCursor = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    private func pickRegion() async -> Region? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }
        return await withCheckedContinuation { continuation in
            result = continuation
            for screen in screens {
                let frame = screen.frame
                let panel = SelectionPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                           backing: .buffered, defer: false)
                panel.level = .screenSaver
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
                panel.hidesOnDeactivate = false
                panel.hasShadow = false
                panel.isOpaque = false
                panel.backgroundColor = .clear
                panel.isReleasedWhenClosed = false
                panel.animationBehavior = .none
                let view = SelectionView(frame: CGRect(origin: .zero, size: frame.size)) { [weak self] rect in
                    self?.finish(rect.map { (screen, $0) })
                }
                panel.contentView = view
                panel.setFrame(frame, display: false)
                panel.makeFirstResponder(view)
                panels.append(panel)
                panel.orderFrontRegardless()
            }
            let hovered = panels.first { $0.frame.contains(NSEvent.mouseLocation) }
            (hovered ?? panels.first)?.makeKey()
        }
    }

    private func finish(_ region: Region?) {
        for panel in panels { panel.orderOut(nil) }
        panels.removeAll()
        result?.resume(returning: region)
        result = nil
    }
}

private final class SelectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class SelectionView: NSView {
    let onFinish: (CGRect?) -> Void
    var anchor: CGPoint?
    var selection = CGRect.zero

    init(frame: CGRect, onFinish: @escaping (CGRect?) -> Void) {
        self.onFinish = onFinish
        super.init(frame: frame)
        setAccessibilityLabel("拖动框选文字，右键或 Esc 取消")
    }

    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { true }
    override var needsPanelToBecomeKey: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill(using: .copy)
        let shade = NSBezierPath(rect: bounds)
        let radius = min(10, selection.width / 2, selection.height / 2)
        let outline = NSBezierPath(roundedRect: selection, xRadius: radius, yRadius: radius)
        shade.append(outline)
        shade.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.30).setFill()
        shade.fill()
        if !selection.isEmpty {
            NSColor(srgbRed: 0.12, green: 0.53, blue: 1, alpha: 1).setStroke()
            outline.lineWidth = 2
            outline.stroke()
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onFinish(nil) }
    }

    override func mouseDown(with event: NSEvent) {
        anchor = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let anchor else { return }
        let end = convert(event.locationInWindow, from: nil)
        selection = CGRect(x: min(anchor.x, end.x), y: min(anchor.y, end.y),
                           width: abs(anchor.x - end.x), height: abs(anchor.y - end.y)).intersection(bounds)
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) {
        onFinish(nil)
    }

    override func mouseUp(with event: NSEvent) {
        mouseDragged(with: event)
        onFinish(selection.isEmpty ? nil : selection)
    }
}
