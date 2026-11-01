import AppKit
import SwiftUI
let logURL = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/snapai-swiftui-drag-probe.NFnju6/events.log")
func record(_ text: String) {
    let data = Data(("\(Date()) \(text)\n").utf8)
    if let h = try? FileHandle(forWritingTo: logURL) { _ = try? h.seekToEnd(); try? h.write(contentsOf: data); try? h.close() }
    else { try? data.write(to: logURL) }
}
struct ProbeContent: View {
    @State private var received = "Drop here"
    var body: some View {
        HStack(spacing: 80) {
            Text("source").frame(width: 200, height: 160).background(Color.blue).foregroundStyle(.white).draggable("fixture")
            Text(received).frame(width: 200, height: 160).background(Color.green)
                .dropDestination(for: String.self, action: { items, point in
                    record("performDrop items=\(items) point=\(point)"); received = items.joined(separator: ", "); return true
                }, isTargeted: { targeted in record("isTargeted=\(targeted)") })
        }.padding(20)
    }
}
final class ProbeHostingView: NSHostingView<ProbeContent> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
final class Probe: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let menu = NSMenu(); let item = NSMenuItem(); let submenu = NSMenu()
        submenu.addItem(withTitle: "退出拖放诊断", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"); item.submenu = submenu; menu.addItem(item); NSApp.mainMenu = menu
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 200), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "SwiftUI Drag Probe"; window.isReleasedWhenClosed = false; window.isOpaque = true; window.isMovableByWindowBackground = false
        window.contentView = ProbeHostingView(rootView: ProbeContent())
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); record("ready content=520x200 sourceCenter=(120,100) targetCenter=(400,100)")
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { record("willTerminate") }
}
let app = NSApplication.shared; app.setActivationPolicy(.accessory)
let delegate = Probe(); app.delegate = delegate; withExtendedLifetime(delegate) { app.run() }
