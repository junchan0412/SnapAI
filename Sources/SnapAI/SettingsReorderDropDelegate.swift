import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let snapAISettingsAction = UTType(exportedAs: "com.snapai.settings-action", conformingTo: .data)
    static let snapAISettingsProvider = UTType(exportedAs: "com.snapai.settings-provider", conformingTo: .data)
}

struct SettingsDragHandle: View {
    let name: String
    let id: String
    let contentType: UTType

    var body: some View {
        SettingsNativeDragSource(payload: "\(contentType.identifier):\(id)", name: name)
            .frame(width: 24, height: 32)
            .help("拖动以调整 \(name) 的顺序")
            .accessibilityLabel("拖动排序 \(name)")
    }
}

private struct SettingsNativeDragSource: NSViewRepresentable {
    let payload: String
    let name: String

    func makeNSView(context: Context) -> SettingsNativeDragSourceView {
        let view = SettingsNativeDragSourceView()
        view.image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
                .applying(.init(paletteColors: [.secondaryLabelColor])))
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.image)
        return view
    }

    func updateNSView(_ view: SettingsNativeDragSourceView, context: Context) {
        view.payload = payload
        view.toolTip = "拖动以调整 \(name) 的顺序"
        view.setAccessibilityLabel("拖动排序 \(name)")
    }
}

private final class SettingsNativeDragSourceView: NSView, NSDraggingSource {
    static var activePayload: String?
    var image: NSImage?
    var payload = ""
    private var isDragging = false
    private var dragStartEvent: NSEvent?

    private var imageFrame: NSRect {
        guard let image else { return .zero }
        return NSRect(x: bounds.midX - image.size.width / 2,
                      y: bounds.midY - image.size.height / 2,
                      width: image.size.width, height: image.size.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        image?.draw(in: imageFrame)
    }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        dragStartEvent = event
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isDragging, let image, let startEvent = dragStartEvent else { return }
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(payload, forType: .string)
        let item = NSDraggingItem(pasteboardWriter: pasteboardItem)
        let preview = NSImage(size: bounds.size)
        preview.lockFocus()
        image.draw(in: imageFrame)
        preview.unlockFocus()
        item.setDraggingFrame(bounds, contents: preview)
        isDragging = true
        Self.activePayload = payload
        beginDraggingSession(with: [item], event: startEvent, source: self)
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint,
                         operation: NSDragOperation) {
        isDragging = false
        dragStartEvent = nil
        Self.activePayload = nil
    }

}

struct SettingsReorderDropModifier<Item: Identifiable>: ViewModifier where Item.ID == String {
    let id: String
    @Binding var items: [Item]
    let contentType: UTType
    var dropTargetID: Binding<String?> = .constant(nil)
    let commit: () -> Void

    func body(content: Content) -> some View {
        content.overlay(SettingsNativeDropReceiver(
            canDrop: canDrop,
            onDrop: moveItem))
    }

    private func canDrop(_ payload: [String]) -> Bool {
        let prefix = "\(contentType.identifier):"
        guard payload.count == 1, let value = payload.first, value.hasPrefix(prefix) else { return false }
        let sourceID = String(value.dropFirst(prefix.count))
        return sourceID != id && items.contains { $0.id == sourceID } && items.contains { $0.id == id }
    }


    func moveItem(_ payload: [String]) -> Bool {
        let prefix = "\(contentType.identifier):"
        guard payload.count == 1, let value = payload.first, value.hasPrefix(prefix) else { return false }
        let sourceID = String(value.dropFirst(prefix.count))
        guard sourceID != id,
              let source = items.firstIndex(where: { $0.id == sourceID }),
              let target = items.firstIndex(where: { $0.id == id }) else { return false }
        items.move(fromOffsets: IndexSet(integer: source), toOffset: target > source ? target + 1 : target)
        commit()
        return true
    }
}

private struct SettingsNativeDropReceiver: NSViewRepresentable {
    let canDrop: ([String]) -> Bool
    let onDrop: ([String]) -> Bool

    func makeNSView(context: Context) -> SettingsNativeDropReceiverView {
        let view = SettingsNativeDropReceiverView()
        view.wantsLayer = true
        view.layer?.cornerRadius = SnapAIUI.cardRadius
        view.registerForDraggedTypes([.string])
        return view
    }

    func updateNSView(_ view: SettingsNativeDropReceiverView, context: Context) {
        view.canDrop = canDrop
        view.onDrop = onDrop
    }
}

private final class SettingsNativeDropReceiverView: NSView {
    var canDrop: ([String]) -> Bool = { _ in false }
    var onDrop: ([String]) -> Bool = { _ in false }

    private func highlight(_ active: Bool) {
        layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.8).cgColor
        layer?.borderWidth = active ? 2 : 0
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let active = SettingsNativeDragSourceView.activePayload,
              canDrop([active]) else { return nil }
        return super.hitTest(point)
    }

    private func payload(_ sender: NSDraggingInfo) -> [String]? {
        guard sender.draggingSourceOperationMask.contains(.copy),
              sender.draggingPasteboard.pasteboardItems?.count == 1,
              let value = sender.draggingPasteboard.string(forType: .string),
              canDrop([value]) else { return nil }
        return [value]
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let valid = payload(sender) != nil
        highlight(valid)
        return valid ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let valid = payload(sender) != nil
        highlight(valid)
        return valid ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { highlight(false) }
    override func draggingEnded(_ sender: NSDraggingInfo) { highlight(false) }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { payload(sender) != nil }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        highlight(false)
        guard let payload = payload(sender) else { return false }
        return onDrop(payload)
    }

}
