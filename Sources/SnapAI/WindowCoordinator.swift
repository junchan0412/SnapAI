import AppKit
import SwiftUI
import SnapAILogic

@MainActor
final class WindowCoordinator: NSObject, NSWindowDelegate {
    private let settings: AppSettings
    private let settingsNavigation = SettingsNavigationModel()
    private let settingsWindowPinState = SettingsWindowPinState()
    private let onSettingsChange: () -> Void
    private let onPinStateChange: () -> Void
    private let onTryQuickInput: () -> Void

    private var settingsWindow: NSWindow?
    private var settingsWindowPinned = false
    private var onboardingWindow: NSWindow?

    init(settings: AppSettings,
         onSettingsChange: @escaping () -> Void,
         onPinStateChange: @escaping () -> Void = {},
         onTryQuickInput: @escaping () -> Void = {}) {
        self.settings = settings
        self.onSettingsChange = onSettingsChange
        self.onPinStateChange = onPinStateChange
        self.onTryQuickInput = onTryQuickInput
        super.init()
    }

    var hasOpenMainWindow: Bool {
        [settingsWindow, onboardingWindow].compactMap { $0 }.contains { $0.isVisible || $0.isMiniaturized }
    }

    var selectedSettingsSection: SettingsSection {
        settingsNavigation.selectedSection
    }

    var isSettingsWindowPinned: Bool {
        settingsWindowPinned
    }

    func closeMainWindows() {
        settingsWindow?.close()
        onboardingWindow?.close()
    }

    func openSettings() {
        showSettings(section: settingsNavigation.selectedSection)
    }

    func showSettings(section: SettingsSection) {
        NSApp.setActivationPolicy(.regular)
        settingsNavigation.select(section)
        if let window = settingsWindow {
            if window.contentViewController == nil {
                window.contentViewController = makeSettingsContentController()
            }
            applySettingsWindowPinnedState(to: window)
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(contentViewController: makeSettingsContentController())
        window.title = "SnapAI 设置"
        window.identifier = NSUserInterfaceItemIdentifier("SnapAI.SettingsWindow")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        // 窗口与内容均使用 behind-window 材质，让桌面真实透出。
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.delegate = self
        window.setContentSize(NSSize(width: 1000, height: 720))
        window.minSize = NSSize(width: 840, height: 620)
        applySettingsWindowPinnedState(to: window)
        window.center()
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    func toggleSettingsWindowPinnedAndShow() {
        setSettingsWindowPinned(!settingsWindowPinned)
        showSettings(section: settingsNavigation.selectedSection)
    }

    func setSettingsWindowPinned(_ pinned: Bool) {
        settingsWindowPinned = pinned
        settingsWindowPinState.isPinned = pinned
        if let settingsWindow {
            applySettingsWindowPinnedState(to: settingsWindow)
            settingsWindow.makeKeyAndOrderFront(nil)
            if pinned {
                settingsWindow.orderFrontRegardless()
            }
        }
        onPinStateChange()
    }

    func showOnboarding() {
        NSApp.setActivationPolicy(.regular)
        if let window = onboardingWindow {
            if window.contentViewController == nil {
                window.contentViewController = makeOnboardingContentController()
            }
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(contentViewController: makeOnboardingContentController())
        window.title = "欢迎使用 SnapAI"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.setContentSize(NSSize(width: 700, height: 620))
        window.minSize = NSSize(width: 600, height: 560)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        onboardingWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closedWindow = notification.object as? NSWindow else { return }
        guard closedWindow === settingsWindow || closedWindow === onboardingWindow else { return }
        let otherMainWindowOpen = [settingsWindow, onboardingWindow].compactMap { $0 }
            .contains { $0 !== closedWindow && ($0.isVisible || $0.isMiniaturized) }
        // 引导窗口被关闭(含红色关闭按钮)即视为完成引导,避免下次启动重复弹出。
        if closedWindow === onboardingWindow && !settings.onboardingDone {
            settings.onboardingDone = true
            settings.save()
            onSettingsChange()
        }
        NSApp.setActivationPolicy(otherMainWindowOpen ? .regular : .accessory)
        DispatchQueue.main.async { [weak self, weak closedWindow] in
            guard let self, let closedWindow else { return }
            guard closedWindow === self.settingsWindow || closedWindow === self.onboardingWindow else { return }
            guard !closedWindow.isVisible else { return }
            closedWindow.contentViewController = nil
        }
    }

    private func makeSettingsContentController() -> NSViewController {
        let view = SettingsView(
            settings: settings,
            navigation: settingsNavigation,
            onChange: onSettingsChange,
            pinState: settingsWindowPinState,
            onPinChange: { [weak self] newValue in
                self?.setSettingsWindowPinned(newValue)
            }
        )
        return NSHostingController(rootView: view)
    }

    private func makeOnboardingContentController() -> NSViewController {
        let view = OnboardingView(settings: settings) { [weak self] in
            guard let self else { return }
            self.settings.onboardingDone = true
            self.settings.save()
            self.onboardingWindow?.close()
            self.onSettingsChange()
        } openSettings: { [weak self] in
            self?.openSettings()
        } onTryQuickInput: { [weak self] in
            self?.onTryQuickInput()
        }
        return NSHostingController(rootView: view)
    }

    private func applySettingsWindowPinnedState(to window: NSWindow) {
        window.level = settingsWindowPinned ? .floating : .normal
    }
}
