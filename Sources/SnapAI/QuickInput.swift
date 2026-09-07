import AppKit
import SwiftUI
import SnapAILogic

/// 快捷输入面板的状态(含图片内容)
@MainActor
final class QuickInputModel: ObservableObject {
    @Published var text: String = ""
    @Published var actionID: String = ""
    @Published private(set) var imageData: Data? = nil   // #3 截图/粘贴的图片
    @Published private(set) var imagePreview: NSImage? = nil
    @Published private(set) var imageMimeType: String = "image/png"
    @Published private(set) var imageNotice: QuickInputImageNotice? = nil
    @Published var isCapturing = false
    /// 发送后短暂为 true,用于在发送按钮上显示「已发送」反馈。
    @Published private(set) var didJustSend = false
    /// 通用瞬时状态(如「诊断已复制」),到期自动清除。
    @Published private(set) var transientStatus: String? = nil
    let settings: AppSettings
    var onSubmit: ((String, AIAction, Data?, String) -> Bool)?

    private var sendFeedbackWork: DispatchWorkItem?
    private var transientWork: DispatchWorkItem?

    init(settings: AppSettings) { self.settings = settings }

    func submit() {
        guard !didJustSend else { return }
        guard !isCapturing else {
            showTransientStatus("截图完成后才能发送", autoDismiss: 1.6)
            return
        }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty || imageData != nil else { return }
        let act = settings.enabledActions.first(where: { $0.id == actionID })
            ?? settings.enabledActions.first
        guard let act = act else { return }
        guard onSubmit?(t, act, imageData, imageMimeType) == true else {
            showTransientStatus("已保留草稿")
            return
        }
        text = ""
        clearImage()
        flashSendConfirmation()
    }

    /// 闪现「已发送」反馈,明确告知用户输入已提交。
    private func flashSendConfirmation() {
        didJustSend = true
        sendFeedbackWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.didJustSend = false }
        sendFeedbackWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1, execute: work)
    }

    /// 展示一条通用瞬时状态(如复制诊断成功),到期自动消失。
    func showTransientStatus(_ text: String, autoDismiss: Double = 1.8) {
        transientWork?.cancel()
        transientStatus = text
        let work = DispatchWorkItem { [weak self] in self?.transientStatus = nil }
        transientWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + autoDismiss, execute: work)
    }

    func clearImage() {
        imageData = nil
        imagePreview = nil
        imageMimeType = "image/png"
        imageNotice = nil
    }

    /// 从剪贴板读取图片(#3)
    func pasteImageFromClipboard() {
        guard let image = NSPasteboard.general
            .readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage else {
            imageNotice = .warning(QuickInputImageStatus.clipboardMissingMessage)
            return
        }
        guard let payload = image.snapAIOptimizedData() else {
            imageNotice = .warning(ScreenCaptureFailureDiagnostic(
                reason: .optimizedImageTooLarge,
                permissionGranted: true,
                output: .missing
            ).userMessage)
            return
        }
        attachImage(payload)
    }

    func attachImage(_ payload: SnapAIImagePayload) {
        guard let preview = NSImage(data: payload.data) else {
            imageNotice = .warning(ScreenCaptureFailureDiagnostic(
                reason: .invalidImage,
                permissionGranted: true,
                output: .missing
            ).userMessage)
            return
        }
        imageData = payload.data
        imagePreview = preview
        imageMimeType = payload.mimeType
        imageNotice = .success(QuickInputImageStatus.optimizedMessage(payload: payload))
    }
}


/// 管理快捷输入面板
@MainActor
final class QuickInputController: NSObject, NSWindowDelegate {
    private var panel: FloatingPanel?
    private var hostingView: NSHostingView<QuickInputView>?
    let model: QuickInputModel
    private let captureQueue = DispatchQueue(label: "com.snapai.screen-capture", qos: .userInitiated)
    /// 记忆上次面板位置,避免每次都强制居中打断用户习惯的位置。
    private var lastOrigin: NSPoint?

    init(model: QuickInputModel) { self.model = model; super.init() }

    func toggle() {
        if let p = panel, p.isVisible { hide() } else { show() }
    }

    func show() {
        let view = QuickInputView(model: model, onClose: { [weak self] in self?.hide() },
                                  onCapture: { [weak self] in self?.captureScreen() })
        let panel: FloatingPanel
        let hosting: NSHostingView<QuickInputView>
        if let existing = self.panel, let existingHosting = hostingView {
            panel = existing
            hosting = existingHosting
            hosting.rootView = view
        } else {
            hosting = NSHostingView(rootView: view)
            panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 340))
            panel.contentView = hosting
            panel.minSize = NSSize(width: 480, height: 300)
            panel.delegate = self
            self.panel = panel
            self.hostingView = hosting
        }
        hosting.layoutSubtreeIfNeeded()
        let fittingSize = hosting.fittingSize
        panel.setContentSize(NSSize(width: max(560, fittingSize.width),
                                    height: max(340, fittingSize.height)))
        if let origin = lastOrigin {
            panel.setFrameOrigin(origin)
        } else if let screen = NSScreen.main {
            let vf = screen.visibleFrame
            let origin = NSPoint(x: vf.midX - panel.frame.width / 2, y: vf.midY + 80)
            panel.setFrameOrigin(origin)
        }
        panel.title = "SnapAI 快捷提问"
        FloatingPanelPresentation.present(panel)
        NSApp.activate(ignoringOtherApps: true)
        if let editor = panel.initialFirstResponder {
            panel.makeFirstResponder(editor)
        }
        installEscMonitor()
    }

    // 窗口移动后记忆位置,下次沿用。
    func windowDidMove(_ notification: Notification) {
        lastOrigin = panel?.frame.origin
    }

    func hide() {
        removeEscMonitor()
        FloatingPanelPresentation.dismiss(panel)
    }

    /// #3 截图:隐藏所有窗口 → 等300ms → 后台运行 screencapture → 重新显示
    private func captureScreen() {
        guard !model.isCapturing else { return }
        model.isCapturing = true
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
        model.isCapturing = false
        visibleWindows.forEach { $0.makeKeyAndOrderFront(nil) }
        switch result {
        case .success(let payload):
            model.attachImage(payload)
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
            model.showTransientStatus("诊断已复制到剪贴板")
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
            guard let self, event.window === self.panel else { return event }
            if let editor = self.panel?.firstResponder as? NSTextView, editor.hasMarkedText() {
                return event
            }
            if event.keyCode == 53 { self.hide(); return nil }
            return event
        }
    }
    private func removeEscMonitor() {
        if let m = escMonitor { NSEvent.removeMonitor(m); escMonitor = nil }
    }
}


// MARK: - NSImage 扩展

struct SnapAIImagePayload {
    var data: Data
    var mimeType: String
}

enum QuickInputImageStatus {
    static let clipboardMissingMessage = "剪贴板中没有可用图片,请先复制图片后再试。"

    static func optimizedMessage(payload: SnapAIImagePayload) -> String {
        let format = payload.mimeType == "image/jpeg" ? "JPEG" : "PNG"
        return "图片已优化为 \(formatByteCount(payload.data.count)) \(format),发送前会按 AI 接口限制校验。"
    }

    private static func formatByteCount(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(max(0, bytes)),
                                  countStyle: .file)
    }
}

struct QuickInputImageNotice {
    var message: String
    var isWarning: Bool

    var systemImage: String {
        isWarning ? "exclamationmark.triangle" : "checkmark.circle"
    }

    static func success(_ message: String) -> Self {
        Self(message: message, isWarning: false)
    }

    static func warning(_ message: String) -> Self {
        Self(message: message, isWarning: true)
    }
}

extension NSImage {
    /// 转换为适合 API 上传的图片数据,限制像素和字节数,避免请求体过大。
    func snapAIOptimizedData(maxPixel: CGFloat = 1600,
                             maxBytes: Int = 2_500_000,
                             maxEncodedBytes: Int = AIClient.maxEncodedImagePayloadBytes) -> SnapAIImagePayload? {
        for pixelLimit in [maxPixel, 1200, 900, 640] {
            let candidate: SnapAIImagePayload? = autoreleasepool {
                guard let resized = snapAIResized(maxPixel: pixelLimit) else { return nil }
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
                return nil
            }
            if let candidate { return candidate }
        }
        return autoreleasepool {
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
