import AppKit
import SnapAILogic

/// 启动装配:`applicationDidFinishLaunching` 的装配动作整体收拢于此。
///
/// 约束(与 SubmissionPipeline 一致):
/// - 只持有 weak host,装配结果写回 AppDelegate 既有存储属性,不产生
///   AppDelegate ⇄ coordinator 的强引用环;
/// - 不新增行为,装配顺序与搬出前逐行一致。
@MainActor
final class LaunchCoordinator {
    private weak var host: AppDelegate?

    private var launchSmokeTimer: Timer?
    private var appearanceObserver: NSObjectProtocol?
    private var frontmostAppObserver: NSObjectProtocol?

    init(host: AppDelegate) {
        self.host = host
    }

    /// 启动 smoke 模式:由 `scripts/run-app-launch-smoke.sh` 注入,正常运行为 false。
    var isLaunchSmoke: Bool {
        host?.launchSmokeDirectory != nil
    }

    func didFinishLaunching() {
        // 覆盖下面的 smoke 早退分支:装配结束即为「菜单栏就绪」。
        defer { LaunchTiming.markReady() }
        guard let host else { return }

        host.applyActivationPolicy()
        host.applyAppIcon()
        installAppearanceObserver()
        installFrontmostAppObserver()
        if host.launchSmokeDirectory == nil {
            host.installAutomationURLHandler()
            iCloudSync.shared.pullIfNeeded(into: host.settings)
        }
        host.windowCoordinator = WindowCoordinator(
            settings: host.settings,
            onSettingsChange: { [weak host] in
                host?.reloadAfterSettingsChange()
            },
            onPinStateChange: { [weak host] in
                host?.installMainMenu()
            },
            onTryQuickInput: { [weak host] in
                host?.toggleQuickInput()
            }
        )

        host.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = host.statusItem.button {
            button.image = host.statusBarImage()
        }

        assembleResultPipeline(host: host)
        assemblePanels(host: host)

        if host.launchSmokeDirectory == nil {
            host.installServicesProvider()
            host.registerHotKeys()
        }
        host.buildMenu()
        host.installMainMenu()

        if completeLaunchSmokeIfNeeded() { return }

        // iCloud 同步监听(#9)。远端配置变化后刷新菜单与快捷键。
        iCloudSync.shared.startListening(into: host.settings) { [weak host] in
            host?.reloadAfterSettingsChange()
        }

        // 首次启动:显示引导;否则按需提示权限
        if !host.settings.onboardingDone {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak host] in
                host?.showOnboarding()
            }
        } else if !TextCapture.hasAccessibilityPermission() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                _ = TextCapture.hasAccessibilityPermission(prompt: true)
            }
        }
    }

    /// 结果面板与提交装配:取词结果 → 面板展示的接线。
    private func assembleResultPipeline(host: AppDelegate) {
        host.resultVM = ResultViewModel(settings: host.settings)
        host.resultVM.onReplace = { [weak host] original, replacement in
            host?.replaceSelection(original: original, with: replacement)
        }
        host.resultVM.onAppend = { [weak host] text in host?.appendSelection(with: text) }   // #8
        host.submissionPipeline = SubmissionPipeline(host: host)
        host.resultVM.prepareFollowUpSubmission = { [weak host] text, action in
            host?.submissionPipeline.prepareTextForSubmission(text,
                                                              action: action,
                                                              imageData: nil,
                                                              userPromptOverride: text)
        }
        host.resultVM.prepareSourceSubmission = { [weak host] text, action in
            host?.submissionPipeline.prepareTextForSubmission(text,
                                                              action: action,
                                                              imageData: nil)
        }
        host.panelController = FloatingPanelController(vm: host.resultVM) { [weak host] in
            host?.showSettings(section: .model)
        }
    }

    /// 快捷提问、命令面板、历史、双模型对照、权限中心窗口的装配。
    private func assemblePanels(host: AppDelegate) {
        host.quickInputModel = QuickInputModel(settings: host.settings)
        host.quickInputModel.actionID = host.settings.enabledActions.first?.id ?? ""
        host.quickInputModel.onSubmit = { [weak host] text, action, imageData, imageMimeType in   // #3 imageData
            host?.runQuickInput(text: text,
                                action: action,
                                imageData: imageData,
                                imageMimeType: imageMimeType) ?? false
        }
        host.quickInput = QuickInputController(model: host.quickInputModel)
        host.commandPalette = CommandPaletteController { [weak host] in
            host?.commandPaletteItems() ?? []
        }
        host.historyWindow = HistoryWindowController(settings: host.settings) { [weak host] entry in
            host?.reopenHistoryEntry(entry)
        }
        host.compareWindow = ModelCompareWindowController()
        host.permissionHealth = PermissionHealthController(
            settings: host.settings,
            hotKeyFailures: { [weak host] in
                host?.hotKeyRegistrationFailures ?? []
            },
            textCaptureStatus: { [weak host] in
                host?.currentTextCaptureStatusSummary() ?? "none"
            },
            writeBackStatus: { [weak host] in
                host?.currentWriteBackStatusSummary() ?? "none"
            },
            recentAIRequestStatus: { [weak host] in
                host?.resultVM.requestHealthStatusText ?? "none"
            }
        )
    }

    private func completeLaunchSmokeIfNeeded() -> Bool {
        guard let host, let directory = host.launchSmokeDirectory, let token = host.launchSmokeToken else {
            return false
        }
        let pid = ProcessInfo.processInfo.processIdentifier
        do {
            try Data("ready \(pid) \(token)\n".utf8)
                .write(to: directory.appendingPathComponent("ready"), options: .atomic)
        } catch {
            NSLog("SnapAI: launch smoke readiness marker failed")
            NSApp.terminate(nil)
            return true
        }
        launchSmokeTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else {
                    timer.invalidate()
                    return
                }
                if FileManager.default.fileExists(atPath: directory.appendingPathComponent("stop").path) {
                    self.launchSmokeTimer?.invalidate()
                    self.launchSmokeTimer = nil
                    NSApp.terminate(nil)
                }
            }
        }
        return true
    }

    func willTerminate() {
        launchSmokeTimer?.invalidate()
        launchSmokeTimer = nil
        guard let host else { return }
        host.settings.save()
        RoutingMetricsStore.shared.flushPersistence()
        if let token = host.launchSmokeToken {
            host.settings.persistenceDefaults.removePersistentDomain(forName: "com.snapai.release-smoke.\(token)")
            let supportDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("SnapAI-LogicTests-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
            try? FileManager.default.removeItem(at: supportDirectory)
        }
    }

    // MARK: - 外观与前台 App 观察

    func installAppearanceObserver() {
        appearanceObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.host?.applyAppIcon()
            }
        }
    }

    func installFrontmostAppObserver() {
        guard let host else { return }
        host.rememberExternalFrontmostApp(NSWorkspace.shared.frontmostApplication)
        frontmostAppObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor [weak self] in
                self?.host?.rememberExternalFrontmostApp(app)
            }
        }
    }
}
