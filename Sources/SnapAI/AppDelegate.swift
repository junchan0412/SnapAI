import AppKit
import SwiftUI
import Carbon
import SnapAILogic

/// 应用入口:只保留状态、NSApplicationDelegate 生命周期与各职责的转发入口。
///
/// 四个职责已拆成 coordinator / builder,单文件不再承载装配细节:
/// - 启动装配 → `LaunchCoordinator`
/// - 菜单栏   → `StatusMenuBuilder` / `MainMenuBuilder`(动作在 `AppDelegate+MenuActions`)
/// - 全局热键 → `HotKeyRegistrationCoordinator`
/// - 面板编排 → `PanelCoordinator`
/// coordinator 只持有 weak host,装配结果写回这里的存储属性,不存在双向强引用。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    let settings: AppSettings
    /// 启动 smoke 上下文:`scripts/run-app-launch-smoke.sh` 注入,正常运行为 nil。
    let launchSmokeDirectory: URL?
    let launchSmokeToken: String?
    var statusItem: NSStatusItem!
    var resultVM: ResultViewModel!
    var panelController: FloatingPanelController!
    var quickInput: QuickInputController!
    var quickInputModel: QuickInputModel!
    var commandPalette: CommandPaletteController!
    var historyWindow: HistoryWindowController!
    var permissionHealth: PermissionHealthController!
    var windowCoordinator: WindowCoordinator!
    var compareWindow: ModelCompareWindowController!
    /// 提交装配(取词→脱敏预览→隐私确认→启动请求),由 LaunchCoordinator 装配。
    var submissionPipeline: SubmissionPipeline!

    // MARK: - 职责 coordinator(lazy:构造需要 self)

    lazy var launch: LaunchCoordinator = LaunchCoordinator(host: self)
    lazy var hotKeys: HotKeyRegistrationCoordinator = HotKeyRegistrationCoordinator(host: self)
    lazy var panels: PanelCoordinator = PanelCoordinator(host: self)

    /// 触发前的前台 App,用于「替换原文」时把焦点交还
    var previousApp: NSRunningApplication?
    var lastExternalFrontmostApp: NSRunningApplication?
    var previousSelectionSnapshot: TextSelectionSnapshot?
    var previousCaptureMethod: TextCaptureMethod?
    var lastTextCaptureStatusSummary: String?
    var lastWriteBackRecord: TextWriteBackRecord?
    var lastWriteBackStatusSummary: String?
    /// 文本捕获代际令牌(#bug2):每次新触发自增,旧捕获回调据此自我作废,避免过期结果弹「未检测到选中文字」。
    var captureGeneration: Int = 0

    override init() {
        settings = AppSettings.shared
        launchSmokeDirectory = nil
        launchSmokeToken = nil
        super.init()
    }

    init(settings: AppSettings, launchSmokeDirectory: URL, launchSmokeToken: String) {
        self.settings = settings
        self.launchSmokeDirectory = launchSmokeDirectory
        self.launchSmokeToken = launchSmokeToken
        super.init()
    }

    // MARK: - NSApplicationDelegate(装配细节在 LaunchCoordinator / PanelCoordinator)

    func applicationDidFinishLaunching(_ notification: Notification) {
        launch.didFinishLaunching()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panels.handleReopen(hasVisibleWindows: flag)
    }

    func applicationWillTerminate(_ notification: Notification) {
        launch.willTerminate()
    }

    // MARK: - 菜单(装配见 StatusMenuBuilder / MainMenuBuilder,动作见 AppDelegate+MenuActions)

    func buildMenu() {
        StatusMenuBuilder.build(for: self)
    }

    func menuActionTitle(for name: String) -> String {
        StatusMenuBuilder.actionTitle(for: name)
    }

    func menuGroupTitle(for group: String) -> String {
        StatusMenuBuilder.groupTitle(for: group)
    }

    func buildWorkModeMenu() -> NSMenu {
        StatusMenuBuilder.workModeMenu(for: self)
    }

    func buildHistoryMenu() -> NSMenu {
        StatusMenuBuilder.historyMenu(for: self)
    }

    func addResultCommandItems(to menu: NSMenu) {
        StatusMenuBuilder.addResultCommands(to: menu, for: self)
    }

    func selector(for action: ResultCommandAction) -> Selector {
        StatusMenuBuilder.selector(for: action)
    }

    func nsModifierFlags(for modifiers: [ResultMenuModifier]) -> NSEvent.ModifierFlags {
        StatusMenuBuilder.modifierFlags(for: modifiers)
    }

    func installMainMenu() {
        MainMenuBuilder.install(for: self)
    }

    // MARK: - Dock / 激活策略 / 前台 App

    func applyActivationPolicy() {
        NSApp.setActivationPolicy(settings.showDockIcon ? .regular : .accessory)
    }

    func applyAppIcon() {
        let name = isDarkAppearance ? "AppIconDark" : "AppIconLight"
        NSApp.applicationIconImage = NSImage(named: name)
    }

    var isDarkAppearance: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    func rememberExternalFrontmostApp(_ app: NSRunningApplication?) {
        guard CaptureTargetResolver.isUsableExternalApp(pid: app?.processIdentifier,
                                                        isTerminated: app?.isTerminated ?? true,
                                                        bundleIdentifier: app?.bundleIdentifier) else {
            return
        }
        lastExternalFrontmostApp = app
    }

    func currentCaptureTargetApp() -> NSRunningApplication? {
        let frontmost = NSWorkspace.shared.frontmostApplication
        rememberExternalFrontmostApp(frontmost)
        return CaptureTargetResolver.resolve(frontmost: frontmost,
                                             lastExternal: lastExternalFrontmostApp)
    }

    func statusBarImage() -> NSImage? {
        let image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "SnapAI")
        image?.isTemplate = true
        return image
    }

    // MARK: - 全局热键(注册与失败清单见 HotKeyRegistrationCoordinator)

    var hotKeyRegistrationFailures: [String] {
        hotKeys.failures
    }

    func registerHotKeys() {
        hotKeys.register()
    }

    func reloadAfterSettingsChange() {
        registerHotKeys()
        quickInputModel.actionID = settings.enabledActions.first(where: { $0.id == quickInputModel.actionID })?.id
            ?? settings.enabledActions.first?.id ?? ""
        buildMenu()
        installMainMenu()
        applyActivationPolicy()
    }

    // MARK: - 面板(编排见 PanelCoordinator,触发装配见 AppDelegate+Submission)

    func toggleQuickInput() {
        panels.toggleQuickInput()
    }

    func showNoSelectionNotice(action: AIAction? = nil) {
        panels.showNoSelectionNotice(action: action)
    }

    func openModelCompare() {
        panels.openModelCompare()
    }

    // MARK: - 设置窗口 / 更新 / 引导

    func openSettings() {
        windowCoordinator.openSettings()
    }

    func showSettings(section: SettingsSection) {
        windowCoordinator.showSettings(section: section)
    }

    func checkForUpdates() {
        UpdateCheckerApp.check()
    }

    func showOnboarding() {
        windowCoordinator.showOnboarding()
    }
}
