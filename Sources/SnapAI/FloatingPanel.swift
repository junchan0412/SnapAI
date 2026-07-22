import AppKit
import SwiftUI

/// 浮动面板统一的淡入/淡出节奏,避免结果窗、快捷提问、命令面板各自硬编码动画。
enum FloatingPanelPresentation {
    static let fadeDuration: TimeInterval = 0.16

    static func present(_ panel: NSPanel, animated: Bool = true) {
        if animated {
            panel.alphaValue = 0
            panel.makeKeyAndOrderFront(nil)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = fadeDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        } else {
            panel.alphaValue = 1
            panel.makeKeyAndOrderFront(nil)
        }
    }

    static func dismiss(_ panel: NSPanel?,
                        animated: Bool = true,
                        completion: (() -> Void)? = nil) {
        guard let panel else {
            completion?()
            return
        }
        let finish = {
            panel.orderOut(nil)
            panel.alphaValue = 1
            completion?()
        }
        if animated && panel.isVisible {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = fadeDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
            }, completionHandler: finish)
        } else {
            finish()
        }
    }
}

/// 一个无标题栏、可成为 key、可调整大小、点击外部自动关闭的浮动面板。
final class FloatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .resizable],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        level = .floating
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        backgroundColor = .clear
        hasShadow = true
        isOpaque = false
        alphaValue = 1
        minSize = NSSize(width: 360, height: 420)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        animationBehavior = .utilityWindow
    }

    // 允许无标题面板成为 key，从而能接收键盘输入(追问框)
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// 管理浮动结果窗口的显示/隐藏与定位
@MainActor
final class FloatingPanelController: NSObject, NSWindowDelegate {
    private var panel: FloatingPanel?
    private var hostingView: NSHostingView<ResultView>?
    private let vm: ResultViewModel
    private let settings: AppSettings
    private let onOpenAISettings: () -> Void
    private var isDismissing = false
    private var localMonitor: Any?
    private var globalMonitor: Any?

    init(vm: ResultViewModel,
         onOpenAISettings: @escaping () -> Void = {}) {
        self.vm = vm
        self.settings = vm.settings
        self.onOpenAISettings = onOpenAISettings
        super.init()
    }

    /// 在鼠标位置附近显示面板
    func show() {
        isDismissing = false
        let rootView = ResultView(vm: vm,
                                  onClose: { [weak self] in self?.hide() },
                                  onOpenAISettings: onOpenAISettings)

        let panel: FloatingPanel
        if let existing = self.panel, let hostingView {
            // 复用 panel 与 hosting 树,只替换 rootView,避免每次触发都重建 SwiftUI 状态树。
            panel = existing
            hostingView.rootView = rootView
        } else {
            let hosting = NSHostingView(rootView: rootView)
            let w = AppSettings.clampedPanelWidth(settings.panelWidth)
            let h = AppSettings.clampedPanelHeight(settings.panelHeight)
            panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: w, height: h))
            panel.contentView = hosting
            panel.delegate = self
            self.panel = panel
            self.hostingView = hosting
        }

        positionNearCursor(panel)
        FloatingPanelPresentation.present(panel)
        NSApp.activate(ignoringOtherApps: true)
        installDismissMonitors()
    }

    func hide() {
        guard !isDismissing else { return }
        isDismissing = true
        vm.cancel()
        removeDismissMonitors()
        FloatingPanelPresentation.dismiss(panel) { [weak self] in
            self?.isDismissing = false
        }
    }

    /// 窗口尺寸变化时记忆(#8)
    func windowDidEndLiveResize(_ notification: Notification) {
        guard let panel = panel else { return }
        settings.panelWidth = AppSettings.clampedPanelWidth(panel.frame.width)
        settings.panelHeight = AppSettings.clampedPanelHeight(panel.frame.height)
        settings.save()
    }

    private func positionNearCursor(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else {
            panel.center(); return
        }
        let size = panel.frame.size
        var origin = NSPoint(x: mouse.x + 12, y: mouse.y - size.height - 12)
        let vf = screen.visibleFrame
        // 防止超出屏幕边界
        if origin.x + size.width > vf.maxX { origin.x = vf.maxX - size.width - 8 }
        if origin.x < vf.minX { origin.x = vf.minX + 8 }
        if origin.y < vf.minY { origin.y = mouse.y + 12 }
        if origin.y + size.height > vf.maxY { origin.y = vf.maxY - size.height - 8 }
        panel.setFrameOrigin(origin)
    }

    // 点击面板外部 / 按 Esc 时关闭(固定状态下不关闭)。
    // 流式生成中点击外部不再静默关闭,避免丢失正在生成的结果;用户可显式固定或关闭。
    // 失焦行为受 resultPanelDismissMode 控制:仅 autoDismiss 注册点外部即关监听器。
    private func installDismissMonitors() {
        removeDismissMonitors()
        let mode = settings.resultPanelDismissMode
        // 仅「自动关闭」模式注册点外部即关的全局监听器;
        // keepAfterResult / alwaysKeep 依靠 Esc / X 按钮 / 写回关闭,点外部不关。
        if mode == .autoDismiss {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                guard let self = self, !self.vm.isPinned else { return }
                if self.vm.isStreaming { return }
                self.hide()
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self = self else { return event }
            if event.keyCode == 53 { // esc
                if self.vm.isStreaming {
                    self.vm.cancel()
                } else if self.vm.isPinned {
                    self.vm.isPinned = false
                } else {
                    self.hide()
                }
                return nil
            }
            return event
        }
    }

    private func removeDismissMonitors() {
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
    }
}
