import AppKit
import SwiftUI

@MainActor
final class WindowCoordinator {
    private let settings: AppSettings
    private let settingsNavigation = SettingsNavigationModel()
    private let settingsWindowPinState = SettingsWindowPinState()
    private let onSettingsChange: () -> Void
    private let onPinStateChange: () -> Void

    private var settingsWindow: NSWindow?
    private var settingsWindowPinned = false
    private var onboardingWindow: NSWindow?

    init(settings: AppSettings,
         onSettingsChange: @escaping () -> Void,
         onPinStateChange: @escaping () -> Void = {}) {
        self.settings = settings
        self.onSettingsChange = onSettingsChange
        self.onPinStateChange = onPinStateChange
    }

    var selectedSettingsSection: SettingsSection {
        settingsNavigation.selectedSection
    }

    var isSettingsWindowPinned: Bool {
        settingsWindowPinned
    }

    func openSettings() {
        showSettings(section: settingsNavigation.selectedSection)
    }

    func showSettings(section: SettingsSection) {
        settingsNavigation.select(section)
        if let window = settingsWindow {
            applySettingsWindowPinnedState(to: window)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SettingsView(
            settings: settings,
            navigation: settingsNavigation,
            onChange: onSettingsChange,
            pinState: settingsWindowPinState,
            onPinChange: { [weak self] newValue in
                self?.setSettingsWindowPinned(newValue)
            }
        )
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "SnapAI 设置"
        window.identifier = NSUserInterfaceItemIdentifier("SnapAI.SettingsWindow")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.setContentSize(NSSize(width: 840, height: 620))
        window.minSize = NSSize(width: 760, height: 560)
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
        if let window = onboardingWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = OnboardingView(settings: settings) { [weak self] in
            guard let self else { return }
            self.settings.onboardingDone = true
            self.settings.save()
            self.onboardingWindow?.close()
            self.onboardingWindow = nil
            self.onSettingsChange()
        } openSettings: { [weak self] in
            self?.openSettings()
        }
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "欢迎使用 SnapAI"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        onboardingWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func applySettingsWindowPinnedState(to window: NSWindow) {
        window.level = settingsWindowPinned ? .floating : .normal
    }
}
