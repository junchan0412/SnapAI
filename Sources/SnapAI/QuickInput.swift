import AppKit
import SwiftUI

/// 快捷输入面板的状态(含图片内容)
@MainActor
final class QuickInputModel: ObservableObject {
    @Published var text: String = ""
    @Published var actionID: String = ""
    @Published var imageData: Data? = nil   // #3 截图/粘贴的图片
    @Published var imageMimeType: String = "image/png"
    @Published var imageWarning: String? = nil
    let settings: AppSettings
    var onSubmit: ((String, AIAction, Data?, String) -> Void)?

    init(settings: AppSettings) { self.settings = settings }

    func submit() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty || imageData != nil else { return }
        let act = settings.enabledActions.first(where: { $0.id == actionID })
            ?? settings.enabledActions.first
        guard let act = act else { return }
        onSubmit?(t, act, imageData, imageMimeType)
        text = ""
        imageData = nil
        imageMimeType = "image/png"
        imageWarning = nil
    }

    /// 从剪贴板读取图片(#3)
    func pasteImageFromClipboard() {
        if let image = NSPasteboard.general.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage {
            if let payload = image.snapAIOptimizedData() {
                imageData = payload.data
                imageMimeType = payload.mimeType
                imageWarning = QuickInputImageStatus.optimizedMessage(payload: payload)
            } else {
                imageWarning = ScreenCaptureFailureDiagnostic(
                    reason: .optimizedImageTooLarge,
                    permissionGranted: true,
                    output: .missing
                ).userMessage
            }
        }
    }
}

struct QuickInputView: View {
    @ObservedObject var model: QuickInputModel
    var onClose: () -> Void
    var onCapture: () -> Void   // 触发截图

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accentColor.opacity(0.16))
                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.tint)
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 1) {
                    Text("SnapAI").font(.headline)
                    Text("快捷提问").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    ForEach(model.settings.enabledActions) { act in
                        Button {
                            model.actionID = act.id
                        } label: {
                            if act.id == model.actionID { Label(act.name, systemImage: "checkmark") }
                            else { Text(act.name) }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: currentActionIcon)
                        Text(currentAction?.name ?? "动作")
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Capsule())
                }
                .menuStyle(.borderlessButton).fixedSize()
            }

            // 图片预览
            if let img = model.imageData, let nsImg = NSImage(data: img) {
                ZStack(alignment: .topTrailing) {
                    Image(nsImage: nsImg).resizable().scaledToFit().frame(maxHeight: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Button { model.imageData = nil } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain).padding(2)
                }
            }
            if let warning = model.imageWarning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            QuickPromptEditor(
                text: $model.text,
                placeholder: "输入你的问题,回车发送…",
                onSubmit: { model.submit() }
            )
            .frame(height: 76)

            HStack {
                // #3 截图 / 粘贴图片
                Button { onCapture() } label: {
                    Label("截图", systemImage: "camera")
                }
                .buttonStyle(.borderless).controlSize(.small).help("截取当前屏幕")
                Button { model.pasteImageFromClipboard() } label: {
                    Label("粘贴图片", systemImage: "photo")
                }
                .buttonStyle(.borderless).controlSize(.small).help("粘贴剪贴板中的图片")

                Spacer()
                Button { model.submit() } label: {
                    Label("发送", systemImage: "paperplane.fill")
                        .font(.callout.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canSubmit)
            }
            .font(.caption)
        }
        .padding(18)
        .frame(width: 500)
        .background(.ultraThinMaterial)
    }

    private var currentAction: AIAction? {
        model.settings.enabledActions.first(where: { $0.id == model.actionID })
            ?? model.settings.enabledActions.first
    }

    private var currentActionIcon: String {
        guard let icon = currentAction?.icon, !icon.isEmpty else {
            return "wand.and.stars"
        }
        return icon
    }

    private var canSubmit: Bool {
        !model.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.imageData != nil
    }
}

/// 管理快捷输入面板
@MainActor
final class QuickInputController: NSObject, NSWindowDelegate {
    private var panel: FloatingPanel?
    let model: QuickInputModel
    private let captureQueue = DispatchQueue(label: "com.snapai.screen-capture", qos: .userInitiated)

    init(model: QuickInputModel) { self.model = model; super.init() }

    func toggle() {
        if let p = panel, p.isVisible { hide() } else { show() }
    }

    func show() {
        let view = QuickInputView(model: model, onClose: { [weak self] in self?.hide() },
                                  onCapture: { [weak self] in self?.captureScreen() })
        let hosting = NSHostingView(rootView: view)
        let panel: FloatingPanel
        if let existing = self.panel {
            panel = existing; panel.contentView = hosting
        } else {
            panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 500, height: 210))
            panel.contentView = hosting; panel.minSize = NSSize(width: 420, height: 180)
            self.panel = panel
        }
        hosting.layoutSubtreeIfNeeded()
        let fittingSize = hosting.fittingSize
        panel.setContentSize(NSSize(width: max(500, fittingSize.width),
                                    height: max(210, fittingSize.height)))
        if let screen = NSScreen.main {
            let vf = screen.visibleFrame
            let origin = NSPoint(x: vf.midX - panel.frame.width / 2, y: vf.midY + 80)
            panel.setFrameOrigin(origin)
        }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        installEscMonitor()
    }

    func hide() { panel?.orderOut(nil); removeEscMonitor() }

    /// #3 截图:隐藏所有窗口 → 等300ms → 后台运行 screencapture → 重新显示
    private func captureScreen() {
        guard ScreenCapturePermission.isGranted() else {
            finishScreenCapture(.failure(ScreenCaptureFailureDiagnostic.missingPermission()),
                                visibleWindows: [])
            return
        }
        let visible = NSApp.windows.filter { $0.isVisible }
        visible.forEach { $0.orderOut(nil) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.runScreenCapture(visibleWindows: visible)
        }
    }

    private func runScreenCapture(visibleWindows: [NSWindow]) {
        let tmpURL = ScreenCaptureTemporaryFile.makeURL()
        captureQueue.async { [weak self] in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            proc.arguments = ["-x", tmpURL.path]   // -x 静音
            let timeout = DispatchWorkItem {
                if proc.isRunning {
                    proc.terminate()
                }
            }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 15, execute: timeout)

            let result: Result<SnapAIImagePayload, Error>
            do {
                try proc.run()
                proc.waitUntilExit()
                timeout.cancel()
                let output = ScreenCaptureOutputSnapshot.make(fileURL: tmpURL)
                guard proc.terminationStatus == 0 else {
                    throw ScreenCaptureFailureDiagnostic(reason: .commandFailed(proc.terminationStatus),
                                                         permissionGranted: true,
                                                         output: output)
                }
                guard output.exists else {
                    throw ScreenCaptureFailureDiagnostic(reason: .outputMissing,
                                                         permissionGranted: true,
                                                         output: output)
                }
                guard (output.byteCount ?? 0) > 0 else {
                    throw ScreenCaptureFailureDiagnostic(reason: .outputEmpty,
                                                         permissionGranted: true,
                                                         output: output)
                }
                let data: Data
                do {
                    data = try Data(contentsOf: tmpURL)
                } catch {
                    throw ScreenCaptureFailureDiagnostic(reason: .unreadableOutput,
                                                         permissionGranted: true,
                                                         output: output)
                }
                guard let image = NSImage(data: data),
                      let payload = image.snapAIOptimizedData() else {
                    throw ScreenCaptureFailureDiagnostic(reason: Self.imagePayloadFailureReason(data: data),
                                                         permissionGranted: true,
                                                         output: output)
                }
                result = .success(payload)
            } catch {
                timeout.cancel()
                result = .failure(error)
            }
            try? FileManager.default.removeItem(at: tmpURL)

            DispatchQueue.main.async { [weak self, result, visibleWindows] in
                self?.finishScreenCapture(result, visibleWindows: visibleWindows)
            }
        }
    }

    private func finishScreenCapture(_ result: Result<SnapAIImagePayload, Error>, visibleWindows: [NSWindow]) {
        visibleWindows.forEach { $0.makeKeyAndOrderFront(nil) }
        switch result {
        case .success(let payload):
            model.imageData = payload.data
            model.imageMimeType = payload.mimeType
            model.imageWarning = QuickInputImageStatus.optimizedMessage(payload: payload)
        case .failure(let error):
            presentScreenCaptureFailure(error)
        }
        show()
    }

    private nonisolated static func imagePayloadFailureReason(data: Data) -> ScreenCaptureFailureDiagnostic.Reason {
        NSImage(data: data) == nil ? .invalidImage : .optimizedImageTooLarge
    }

    private func presentScreenCaptureFailure(_ error: Error) {
        let diagnostic = error as? ScreenCaptureFailureDiagnostic
            ?? ScreenCaptureFailureDiagnostic(reason: .unreadableOutput,
                                              permissionGranted: ScreenCapturePermission.isGranted(),
                                              output: .missing)
        let alert = NSAlert()
        alert.messageText = "截图失败"
        alert.informativeText = diagnostic.userMessage
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        alert.addButton(withTitle: "打开屏幕录制设置")
        alert.addButton(withTitle: "复制诊断")

        switch alert.runModal() {
        case .alertSecondButtonReturn:
            openScreenRecordingSettings()
        case .alertThirdButtonReturn:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(diagnostic.shareableText, forType: .string)
        default:
            break
        }
    }

    private func openScreenRecordingSettings() {
        NSWorkspace.shared.open(SystemPrivacySettings.screenCaptureURL)
    }

    private var escMonitor: Any?
    private func installEscMonitor() {
        removeEscMonitor()
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 { self?.hide(); return nil }
            return event
        }
    }
    private func removeEscMonitor() {
        if let m = escMonitor { NSEvent.removeMonitor(m); escMonitor = nil }
    }
}

// MARK: - 多行快捷提问输入框

struct QuickPromptEditor: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onSubmit: () -> Void

    func makeNSView(context: Context) -> PromptEditorContainer {
        let container = PromptEditorContainer()
        let scrollView = container.scrollView
        let textView = container.textView

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        textView.placeholderString = placeholder
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = .labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 7)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.lineBreakMode = .byWordWrapping
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false

        scrollView.documentView = textView
        container.install(scrollView)
        return container
    }

    func updateNSView(_ container: PromptEditorContainer, context: Context) {
        let scrollView = container.scrollView
        let textView = container.textView
        context.coordinator.parent = self
        textView.placeholderString = placeholder
        if textView.string != text {
            textView.string = text
            textView.needsDisplay = true
        }
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width,
                                                       height: CGFloat.greatestFiniteMagnitude)

        guard !context.coordinator.didAttemptFocus else { return }
        context.coordinator.didAttemptFocus = true
        DispatchQueue.main.async {
            container.window?.makeFirstResponder(textView)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: QuickPromptEditor
        var didAttemptFocus = false

        init(_ parent: QuickPromptEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            textView.needsDisplay = true
        }

        func textDidBeginEditing(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            (textView.enclosingScrollView?.superview as? PromptEditorContainer)?.isFocused = true
        }

        func textDidEndEditing(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            (textView.enclosingScrollView?.superview as? PromptEditorContainer)?.isFocused = false
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else {
                return false
            }
            let flags = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
            if flags.contains(.shift) || flags.contains(.option) {
                return false
            }
            parent.onSubmit()
            return true
        }
    }
}

final class PromptEditorContainer: NSView {
    let scrollView = NSScrollView()
    let textView = PlaceholderTextView()
    var isFocused = false {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    func install(_ scrollView: NSScrollView) {
        guard scrollView.superview == nil else { return }
        addSubview(scrollView)
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds.insetBy(dx: 3, dy: 3)
        let contentSize = scrollView.contentSize
        textView.frame = NSRect(x: 0,
                                y: 0,
                                width: contentSize.width,
                                height: max(contentSize.height, textView.frame.height))
        textView.textContainer?.containerSize = NSSize(width: contentSize.width,
                                                       height: CGFloat.greatestFiniteMagnitude)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let borderWidth: CGFloat = isFocused ? 3 : 1
        let rect = bounds.insetBy(dx: borderWidth / 2, dy: borderWidth / 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        NSColor.textBackgroundColor.withAlphaComponent(0.72).setFill()
        path.fill()
        (isFocused ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = borderWidth
        path.stroke()
    }
}

final class PlaceholderTextView: NSTextView {
    var placeholderString: String = "" {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholderString.isEmpty else { return }

        let rect = NSRect(
            x: textContainerInset.width + 4,
            y: textContainerInset.height,
            width: bounds.width - textContainerInset.width * 2 - 8,
            height: bounds.height - textContainerInset.height * 2
        )
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.placeholderTextColor,
            .paragraphStyle: paragraph
        ]
        placeholderString.draw(in: rect, withAttributes: attributes)
    }
}

// MARK: - NSImage 扩展

struct SnapAIImagePayload {
    var data: Data
    var mimeType: String
}

enum QuickInputImageStatus {
    static func optimizedMessage(payload: SnapAIImagePayload) -> String {
        let format = payload.mimeType == "image/jpeg" ? "JPEG" : "PNG"
        return "图片已优化为 \(formatByteCount(payload.data.count)) \(format),发送前会按 AI 接口限制校验。"
    }

    private static func formatByteCount(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(max(0, bytes)),
                                  countStyle: .file)
    }
}

extension NSImage {
    /// 转换为适合 API 上传的图片数据,限制像素和字节数,避免请求体过大。
    func snapAIOptimizedData(maxPixel: CGFloat = 1600,
                             maxBytes: Int = 2_500_000,
                             maxEncodedBytes: Int = AIClient.maxEncodedImagePayloadBytes) -> SnapAIImagePayload? {
        for pixelLimit in [maxPixel, 1200, 900, 640] {
            guard let resized = snapAIResized(maxPixel: pixelLimit) else { continue }
            if let png = resized.snapAIImageData(type: .png),
               png.count <= maxBytes,
               Self.snapAIEncodedPayloadFits(data: png,
                                             mimeType: "image/png",
                                             maxEncodedBytes: maxEncodedBytes) {
                return SnapAIImagePayload(data: png, mimeType: "image/png")
            }
            for quality in [0.82, 0.68, 0.52, 0.42] {
                if let jpeg = resized.snapAIImageData(type: .jpeg, compression: quality),
                   jpeg.count <= maxBytes,
                   Self.snapAIEncodedPayloadFits(data: jpeg,
                                                 mimeType: "image/jpeg",
                                                 maxEncodedBytes: maxEncodedBytes) {
                    return SnapAIImagePayload(data: jpeg, mimeType: "image/jpeg")
                }
            }
        }
        guard let fallback = snapAIResized(maxPixel: 640)?
            .snapAIImageData(type: .jpeg, compression: 0.36) else { return nil }
        guard fallback.count <= maxBytes,
              Self.snapAIEncodedPayloadFits(data: fallback,
                                            mimeType: "image/jpeg",
                                            maxEncodedBytes: maxEncodedBytes) else {
            return nil
        }
        return SnapAIImagePayload(data: fallback, mimeType: "image/jpeg")
    }

    private static func snapAIEncodedPayloadFits(data: Data,
                                                 mimeType: String,
                                                 maxEncodedBytes: Int) -> Bool {
        AIClient.encodedImagePayloadByteCount(dataByteCount: data.count,
                                              mimeType: mimeType) <= maxEncodedBytes
    }

    private func snapAIResized(maxPixel: CGFloat) -> NSImage? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let largest = max(width, height)
        let scale = largest > maxPixel ? maxPixel / largest : 1
        let targetSize = NSSize(width: max(1, floor(width * scale)),
                                height: max(1, floor(height * scale)))
        let resized = NSImage(size: targetSize)
        resized.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        draw(in: NSRect(origin: .zero, size: targetSize),
             from: NSRect(origin: .zero, size: size),
             operation: .copy,
             fraction: 1)
        resized.unlockFocus()
        return resized
    }

    private func snapAIImageData(type: NSBitmapImageRep.FileType,
                                 compression: Double = 0.8) -> Data? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        var properties: [NSBitmapImageRep.PropertyKey: Any] = [:]
        if type == .jpeg {
            properties[.compressionFactor] = compression
        }
        return rep.representation(using: type, properties: properties)
    }
}
