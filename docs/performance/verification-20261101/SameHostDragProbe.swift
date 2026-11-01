import AppKit
import SwiftUI
let logURL = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/snapai-cross-drag-probe.tUGuov/samehost-events.log")
func record(_ text: String) {
    let data = Data(("\(Date()) \(text)\n").utf8)
    if let h = try? FileHandle(forWritingTo: logURL) { _ = try? h.seekToEnd(); try? h.write(contentsOf: data); try? h.close() }
    else { try? data.write(to: logURL) }
}
final class NativeView: NSView, NSDraggingSource {
    let source: Bool; var dragging = false; var received = ""
    init(frame: NSRect, source: Bool) { self.source = source; super.init(frame: frame); if !source { registerForDraggedTypes([.string]) } }
    required init?(coder: NSCoder) { fatalError() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        (source ? NSColor.systemBlue : NSColor.systemGreen).setFill(); bounds.fill()
        let text = received.isEmpty ? (source ? "B: Native source" : "A: Native target") : received
        text.draw(at: NSPoint(x: 20, y: 74), withAttributes: [.font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor.white])
    }
    override func mouseDown(with e: NSEvent) { record("Native mouseDown source=\(source) local=\(convert(e.locationInWindow, from: nil))") }
    override func mouseDragged(with e: NSEvent) {
        record("Native mouseDragged source=\(source)"); guard source, !dragging else { return }; dragging = true
        let pb = NSPasteboardItem(); pb.setString("fixture-native", forType: .string); let item = NSDraggingItem(pasteboardWriter: pb)
        let image = NSImage(size: bounds.size); image.lockFocus(); NSColor.systemBlue.setFill(); bounds.fill(); image.unlockFocus()
        item.setDraggingFrame(bounds, contents: image); _ = beginDraggingSession(with: [item], event: e, source: self); record("B Native beginDraggingSession")
    }
    override func mouseUp(with e: NSEvent) { record("Native mouseUp source=\(source)") }
    func draggingSession(_ s: NSDraggingSession, sourceOperationMaskFor c: NSDraggingContext) -> NSDragOperation { .copy }
    func draggingSession(_ s: NSDraggingSession, endedAt p: NSPoint, operation o: NSDragOperation) { dragging = false; record("B Native endedAt=\(p) operation=\(o.rawValue)") }
    func details(_ s: NSDraggingInfo) -> String { "types=\(s.draggingPasteboard.types?.map(\.rawValue) ?? []) string=\(s.draggingPasteboard.string(forType: .string) ?? "nil") sourceMask=\(s.draggingSourceOperationMask.rawValue) location=\(s.draggingLocation)" }
    override func draggingEntered(_ s: NSDraggingInfo) -> NSDragOperation { record("A Native entered " + details(s)); return .copy }
    override func draggingUpdated(_ s: NSDraggingInfo) -> NSDragOperation { record("A Native updated " + details(s)); return .copy }
    override func draggingExited(_ s: NSDraggingInfo?) { record("A Native exited") }
    override func prepareForDragOperation(_ s: NSDraggingInfo) -> Bool { record("A Native prepare " + details(s)); return true }
    override func performDragOperation(_ s: NSDraggingInfo) -> Bool { record("A Native performDrop " + details(s)); received = s.draggingPasteboard.string(forType: .string) ?? "nil"; needsDisplay = true; return received != "nil" }
}
struct NativeSourceView: NSViewRepresentable {
    func makeNSView(context: Context) -> NativeView { NativeView(frame: .zero, source: true) }
    func updateNSView(_ view: NativeView, context: Context) {}
}
struct ProbeContent: View {
    @State private var received = "SwiftUI target in same host"
    var body: some View { HStack(spacing: 140) {
        NativeSourceView().frame(width: 220, height: 160)
        Text(received).frame(width: 220, height: 160).background(Color.green)
            .dropDestination(for: String.self, action: { items, point in record("SameHost performDrop items=\(items) point=\(point)"); received = items.joined(separator: ", "); return true },
                isTargeted: { value in record("SameHost isTargeted=\(value)") })
    }.padding(20) }
}
final class ProbeHostingView: NSHostingView<ProbeContent> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
final class Probe: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory); let menu = NSMenu(); let item = NSMenuItem(); let submenu = NSMenu()
        submenu.addItem(withTitle: "退出拖放诊断", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"); item.submenu = submenu; menu.addItem(item); NSApp.mainMenu = menu
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 200), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Same Host Drag Probe"; window.isReleasedWhenClosed = false; window.isOpaque = true; window.isMovableByWindowBackground = false
        window.contentView = ProbeHostingView(rootView: ProbeContent())
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); record("ready content=620x200 source=(130,100) target=(490,100)")
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { record("willTerminate") }
}
let app = NSApplication.shared; app.setActivationPolicy(.accessory); let delegate = Probe(); app.delegate = delegate; withExtendedLifetime(delegate) { app.run() }
