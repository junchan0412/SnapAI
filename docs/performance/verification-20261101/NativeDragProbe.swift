import AppKit
let logURL = URL(fileURLWithPath: CommandLine.arguments[1])
let fixtureID = "snapai-native-drag-fixture"
func record(_ text: String) {
    let data = Data(("\(Date()) \(text)\n").utf8)
    if let h = try? FileHandle(forWritingTo: logURL) {
        try? h.seekToEnd(); try? h.write(contentsOf: data); try? h.close()
    } else { try? data.write(to: logURL) }
}
final class ProbeView: NSView, NSDraggingSource {
    let source: Bool
    var dragging = false
    init(frame: NSRect, source: Bool) {
        self.source = source; super.init(frame: frame)
        if !source { registerForDraggedTypes([.string]) }
        setAccessibilityElement(true); setAccessibilityRole(.group)
        setAccessibilityLabel(source ? "Drag source" : "Drop target")
    }
    required init?(coder: NSCoder) { fatalError() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        (source ? NSColor.systemBlue : NSColor.systemGreen).withAlphaComponent(0.2).setFill(); bounds.fill()
        (source ? "Drag fixture from here" : "Drop fixture here").draw(at: NSPoint(x: 15, y: 74),
            withAttributes: [.font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor.labelColor])
    }
    override func mouseDown(with e: NSEvent) { record("mouseDown source=\(source) local=\(convert(e.locationInWindow, from: nil))") }
    override func mouseDragged(with e: NSEvent) {
        record("mouseDragged source=\(source) local=\(convert(e.locationInWindow, from: nil))")
        guard source, !dragging else { return }; dragging = true
        let pasteboard = NSPasteboardItem(); pasteboard.setString(fixtureID, forType: .string)
        let item = NSDraggingItem(pasteboardWriter: pasteboard)
        let image = NSImage(size: bounds.size); image.lockFocus(); NSColor.systemBlue.setFill(); bounds.fill(); image.unlockFocus()
        item.setDraggingFrame(bounds, contents: image)
        let session = beginDraggingSession(with: [item], event: e, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = false; record("beginDraggingSession")
    }
    override func mouseUp(with e: NSEvent) { record("mouseUp source=\(source) local=\(convert(e.locationInWindow, from: nil))") }
    func draggingSession(_ s: NSDraggingSession, sourceOperationMaskFor c: NSDraggingContext) -> NSDragOperation { .copy }
    func draggingSession(_ s: NSDraggingSession, endedAt p: NSPoint, operation o: NSDragOperation) { dragging = false; record("source endedAt=\(p) operation=\(o.rawValue)") }
    override func draggingEntered(_ s: NSDraggingInfo) -> NSDragOperation { record("draggingEntered location=\(s.draggingLocation)"); return .copy }
    override func draggingUpdated(_ s: NSDraggingInfo) -> NSDragOperation { record("draggingUpdated location=\(s.draggingLocation)"); return .copy }
    override func draggingExited(_ s: NSDraggingInfo?) { record("draggingExited") }
    override func prepareForDragOperation(_ s: NSDraggingInfo) -> Bool { record("prepareDrop"); return true }
    override func performDragOperation(_ s: NSDraggingInfo) -> Bool { let value = s.draggingPasteboard.string(forType: .string); record("performDrop value=\(value ?? "nil")"); return value == fixtureID }
}
final class Probe: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let menu = NSMenu(); let appItem = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出拖放诊断", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"); appItem.submenu = appMenu; menu.addItem(appItem); NSApp.mainMenu = menu
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 240), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "SnapAI Native Drag Probe"; window.isReleasedWhenClosed = false; window.isMovableByWindowBackground = false
        window.contentView!.addSubview(ProbeView(frame: NSRect(x: 20, y: 40, width: 200, height: 160), source: true))
        window.contentView!.addSubview(ProbeView(frame: NSRect(x: 320, y: 40, width: 220, height: 160), source: false))
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); record("ready content=560x240 sourceCenter=(120,120) targetCenter=(430,120)")
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { record("willTerminate") }
}
let app = NSApplication.shared; app.setActivationPolicy(.accessory)
let delegate = Probe(); app.delegate = delegate; withExtendedLifetime(delegate) { app.run() }
