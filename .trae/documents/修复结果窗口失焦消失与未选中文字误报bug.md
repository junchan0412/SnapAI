# 修复结果窗口失焦消失与「未检测到选中文字」误报

## Summary

本次修复针对用户报告的两个明确 bug，范围严格限定在这两个问题上，不做额外扫描和重构：

1. **Bug 1（结果窗口点击外部即消失）**：结果浮窗（FloatingPanel）通过全局鼠标按下监听器在用户点击任何其他窗口时强制 `hide()`，且仅当用户手动 Pin 后才不消失。本次新增设置项「结果窗口失焦行为」，让用户可选「自动关闭 / 生成后保持 / 始终保持」三种策略，默认改为对用户更友好的行为。

2. **Bug 2（动作已在执行却提示未检测到选中文字）**：异步文本捕获 `TextCapture.captureDetailed` 无并发守卫，过期捕获的回调仍会调用模态 `notifyNoSelection` alert。本次引入捕获代际令牌（generation token）使旧捕获回调失效，并在回调与 alert 入口加 `isStreaming` 守卫；同时将「未检测到选中文字」从阻塞式模态 alert 改为结果窗口已有的非模态横幅机制。

## Current State Analysis

### Bug 1 现状

- `Sources/SnapAI/FloatingPanel.swift:108-114`：`installDismissMonitors()` 装了一个 `addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown])` 全局监听器，当 `!isPinned && !isStreaming` 时点击外部即 `hide()`。
- `Sources/SnapAI/FloatingPanel.swift:76-80`：`hide()` 调用 `vm.cancel()` + `panel?.orderOut(nil)` + `removeDismissMonitors()`。
- `Sources/SnapAI/ResultViewModel.swift:13`：`@Published var isPinned: Bool = false`，默认不固定。
- `Sources/SnapAI/AppDelegate.swift:61`：`resultVM` 是单例，`isPinned` 跨次保留，但新结果默认仍是 false（`start()` 不重置，见 `ResultViewModel.swift:160-182`）。
- `AppSettings` 中没有任何「浮窗失焦行为」开关（已全仓搜索确认）。
- Pin 按钮文案 `ResultView.swift:85` 已说明「未固定时点击面板外部或按 Esc 将关闭」。

### Bug 2 现状

- `Sources/SnapAI/AppDelegate.swift:606-637`：`triggerCapturedSelection` 调用异步 `TextCapture.captureDetailed`，回调里 **没有任何 `isStreaming` 检查、没有捕获代际令牌**。`AppDelegate.swift:617-621`：捕获到空文本即调用 `notifyNoSelection(action:)`。
- `Sources/SnapAI/AppDelegate.swift:734-759`：`notifyNoSelection` 弹出 **模态** `NSAlert.runModal()`，阻塞且抢焦点。
- `Sources/SnapAI/AppDelegate.swift:618`：空文本分支还会先调 `recordTextCaptureOutcome`（`AppDelegate+WriteBack.swift:205-224`），把 `lastTextCaptureStatusSummary` 覆写为 `noSelection`，污染菜单诊断。
- `TextCapture.swift:133-187`：捕获在后台线程，最坏情况（AX 失败 + 目标激活重试 + 3 轮剪贴板兜底）耗时数秒；期间用户可能已触发新动作或结果浮窗已抢焦点导致选区失效。
- 唯一调用 `notifyNoSelection` 的地方是 `AppDelegate.swift:619`（已确认）。
- 结果窗口已有非模态横幅机制 `SnapAIIncompleteResultBanner`（`SnapAIUI.swift:238`）和 `incompleteResultReason`（`ResultViewModel.swift:43`）。

### 现有可复用机制

- 设置项模式：`Sources/SnapAI/Settings.swift` 的 `@Published` + `CodingKeys` + `init(from:)` + `encode(to:)` + `AppSettingsImportSanitization.swift` 导出清理。
- 设置 UI 模式：`GeneralSettingsSection.swift` 的 `settingsToggleRow` / `settingsSection`。
- 非模态横幅：`SnapAIIncompleteResultBanner`、QuickInput 的 `showTransientStatus`（`QuickInput.swift:49`）。
- 设计色：`SnapAIUI.StatusColor.warning/error`（`SnapAIUI.swift:22`）。

## Proposed Changes

### 改动 1：新增设置项「结果窗口失焦行为」

**文件：`Sources/SnapAI/Settings.swift`**

1. 新增枚举（放在 `AppSettings` 类外或合适位置）：
   ```swift
   enum ResultPanelDismissMode: String, CaseIterable, Codable {
       case autoDismiss      // 点外部即关（旧行为）
       case keepAfterResult  // 生成完成后保持，仅 Esc/X/写回关闭
       case alwaysKeep       // 始终保持，仅 Esc/X/写回关闭

       var title: String {
           switch self {
           case .autoDismiss: return "自动关闭"
           case .keepAfterResult: return "生成后保持"
           case .alwaysKeep: return "始终保持"
           }
       }
       var description: String {
           switch self {
           case .autoDismiss: return "点击结果窗口外部即关闭（需手动固定才能保留）。"
           case .keepAfterResult: return "结果生成完成后点击外部不关闭；生成中点击外部也不关闭。"
           case .alwaysKeep: return "始终保留，仅按 Esc、点关闭按钮或写回原文时关闭。"
           }
       }
   }
   ```
2. 在 `@Published` 区（`Settings.swift:86` 附近）新增：
   ```swift
   @Published var resultPanelDismissMode: ResultPanelDismissMode = .keepAfterResult
   ```
   默认值用 `.keepAfterResult`，直接解决用户痛点（不再点一下就消失），同时保留旧用户可切回 `.autoDismiss`。
3. `CodingKeys`（`Settings.swift:182`）新增 `case resultPanelDismissMode`。
4. `init(from:)`（`Settings.swift:291` 附近 panelHeight 解码之后）新增：
   ```swift
   resultPanelDismissMode = (try? c.decode(ResultPanelDismissMode.self, forKey: .resultPanelDismissMode)) ?? .keepAfterResult
   ```
5. `encode(to:)`（`Settings.swift:392` 之后）新增：
   ```swift
   try c.encode(resultPanelDismissMode, forKey: .resultPanelDismissMode)
   ```

**文件：`Sources/SnapAI/AppSettingsImportSanitization.swift`**

6. `exportConfigurationData()`（line 12 附近）新增，导出时不带本机偏好：
   ```swift
   exportSettings.resultPanelDismissMode = .keepAfterResult
   ```

**文件：`Sources/SnapAI/FloatingPanel.swift`**

7. 改造 `installDismissMonitors()` 的全局监听器（line 110-114），按 `settings.resultPanelDismissMode` 决定是否注册点外部关闭：
   ```swift
   private func installDismissMonitors() {
       removeDismissMonitors()
       let mode = settings.resultPanelDismissMode
       // 仅「自动关闭」模式注册点外部即关的全局监听器；其余模式靠 Esc/X/写回关闭。
       if mode == .autoDismiss {
           globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
               guard let self = self, !self.vm.isPinned else { return }
               if self.vm.isStreaming { return }
               self.hide()
           }
       }
       localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
           // Esc 逻辑保持不变
           ...
       }
   }
   ```
   注意：`keepAfterResult` 与 `alwaysKeep` 都不注册全局鼠标监听器；`isStreaming` 的保护仍保留（对 autoDismiss 模式生效）。Esc 监听对所有模式保留（用户始终可用 Esc 关闭/取消）。

### 改动 2：设置 UI 暴露「结果窗口失焦行为」

**文件：`Sources/SnapAI/GeneralSettingsSection.swift`**

8. 在 `launchAndDisplaySection`（line 29-49）的 Dock 图标 toggle 后追加一个 Picker 行（复用现有 `settingsSection` 容器，用 `compactDivider` 分隔）：
   ```swift
   compactDivider
   resultPanelDismissRow
   ```
   新增私有计算属性 `resultPanelDismissRow`，模仿 `typewriterSpeedRow`（line 97-115）的布局：左侧标题+描述，右侧 `Picker("", selection: $settings.resultPanelDismissMode)` 用 `.segmented` 样式，`.onChange(of: settings.resultPanelDismissMode) { commit() }`。

### 改动 3：Bug 2 — 捕获代际令牌 + isStreaming 守卫

**文件：`Sources/SnapAI/AppDelegate.swift`**

9. 在实例变量区（`AppDelegate.swift:20-29` 附近）新增捕获代际计数器：
   ```swift
   private var captureGeneration: Int = 0
   ```

10. 改造 `triggerCapturedSelection`（`AppDelegate.swift:606-637`）：
    - 入口处 `captureGeneration += 1`，捕获本次 `let gen = captureGeneration`。
    - 在 `TextCapture.captureDetailed` 回调开头加：
      ```swift
      guard gen == self.captureGeneration else { return }  // 过期捕获丢弃
      guard !self.resultVM.isStreaming else { return }     // 已有动作在跑则丢弃
      ```
    - 空文本分支不再无条件调 `notifyNoSelection`，改为调新的非模态提示（见改动 4）。
    - `recordTextCaptureOutcome` 仅在 `gen == self.captureGeneration` 时调用，避免过期捕获污染诊断摘要。

    改造后的核心结构：
    ```swift
    func triggerCapturedSelection(action: AIAction, preferredTarget:..., forceDismissTransientUIBeforeCopy: Bool = false) {
        captureGeneration += 1
        let gen = captureGeneration
        previousApp = captureTargetApp(preferredTarget: preferredTarget)
        previousSelectionSnapshot = nil
        previousCaptureMethod = nil
        TextCapture.captureDetailed(...) { [weak self] outcome in
            guard let self = self else { return }
            guard gen == self.captureGeneration else { return }
            guard !self.resultVM.isStreaming else { return }
            let text = outcome.usableText
            guard let text = text, !text.isEmpty else {
                self.recordTextCaptureOutcome(outcome)
                self.showNoSelectionNotice(action: action)  // 非模态
                return
            }
            self.recordTextCaptureOutcome(outcome)
            ...
        }
    }
    ```

11. `triggerAction`（`AppDelegate.swift:601-604`）入口无需额外守卫——代际令牌已保证「新触发使旧捕获失效」。但为避免无谓的后台捕获开销，可在入口加一个轻量判断：若 `resultVM.isStreaming`，先 `resultVM.cancel()` 再继续（让用户显式覆盖当前动作）。此为可选增强，保守起见本次采用「丢弃旧捕获」而非「取消当前流」，因此 **不** 在 triggerAction 入口加 cancel，仅依赖回调里的 `!isStreaming` 守卫丢弃过期结果。

### 改动 4：Bug 2 — 「未检测到选中文字」改为非模态提示

**文件：`Sources/SnapAI/AppDelegate.swift`**

12. 将 `notifyNoSelection(action:)`（line 734-759）重命名为 `showNoSelectionNotice(action:)`，行为改为：若结果浮窗可见则用结果窗口的非模态横幅提示，否则回退到原模态 alert（保留模态作为「无浮窗时的兜底」，避免完全静默）。

    实现：在 `ResultViewModel` 新增一个瞬时提示字段（见改动 5），`showNoSelectionNotice` 设置该字段并 `panelController.show()`（若未显示），不再 `runModal`。

    ```swift
    func showNoSelectionNotice(action: AIAction?) {
        // 已有动作在跑则不打扰
        guard !resultVM.isStreaming else { return }
        resultVM.showTransientNotice(TextCaptureRecoveryGuide.title)
        panelController.show()
    }
    ```
    保留原模态 alert 作为「无浮窗且非流式」兜底的判断移除——直接用非模态。原 alert 的「打开快捷提问/权限健康/辅助功能」入口收拢到横幅的一个「查看帮助」按钮（或保持横幅纯提示，用户可从菜单进权限中心）。**为降低复杂度，本次横幅仅显示文案 + 一个「打开快捷提问」按钮**，其余入口用户可从状态栏菜单进入。

**文件：`Sources/SnapAI/ResultViewModel.swift`**

13. 新增瞬时提示状态（模仿 `incompleteResultReason` 与 QuickInput 的 `transientStatus`）：
    ```swift
    @Published var transientNotice: TransientNotice?
    ```
    其中 `TransientNotice` 是轻量结构（message + 可选 actionTitle）。新增方法：
    ```swift
    func showTransientNotice(_ message: String) {
        transientNotice = TransientNotice(message: message)
        let work = DispatchWorkItem { [weak self] in self?.transientNotice = nil }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: work)
    }
    func dismissTransientNotice() { transientNotice = nil }
    ```

**文件：`Sources/SnapAI/ResultView.swift`**

14. 在结果窗口 body 中挂一个非模态横幅（复用 `SnapAIIncompleteResultBanner` 的视觉风格或新建一个 `SnapAITransientNoticeBanner`），当 `vm.transientNotice != nil` 时显示，带「打开快捷提问」按钮（调用 `onOpenAISettings` 类似的回调链——但此处需要「打开快捷提问」回调，需在 `ResultView` 新增 `onOpenQuickInput` 闭包，由 `FloatingPanelController.show()` 注入）。

    为最小化改动，**横幅仅显示文案 + 关闭按钮**，「打开快捷提问」入口由用户从状态栏菜单或快捷键进入。这样 `ResultView` 无需新增回调链。

    ```swift
    if let notice = vm.transientNotice {
        SnapAITransientNoticeBanner(title: notice.message, onDismiss: { vm.dismissTransientNotice() })
    }
    ```

**文件：`Sources/SnapAI/SnapAIUI.swift`**

15. 新增 `SnapAITransientNoticeBanner` 视图（紧邻 `SnapAIIncompleteResultBanner`，line 238 附近），视觉风格一致但用 `StatusColor.warning`，带关闭按钮。

### 改动 6：清理旧的模态 alert 调用

**文件：`Sources/SnapAI/AppDelegate.swift`**

16. 原 `notifyNoSelection` 函数体（line 734-759）替换为 `showNoSelectionNotice`（改动 4）。删除 `runModal` 阻塞逻辑。原 alert 的 4 个按钮（好/快捷提问/权限健康/辅助功能）精简：横幅只留「关闭」，其余入口用户从菜单进入。

    全仓确认 `notifyNoSelection` 是否有其他调用点（探索报告显示唯一调用点是 line 619，本次已改为 `showNoSelectionNotice`）。需 grep 确认无残留。

## Assumptions & Decisions

1. **默认值决策**：`resultPanelDismissMode` 默认 `.keepAfterResult` 而非 `.autoDismiss`，直接解决用户痛点。旧用户升级后也会获得新默认（更友好），想恢复旧行为可在设置切回 `.autoDismiss`。
2. **不引入 Pin 持久化**：Pin 仍是内存态布尔，与本次设置项正交。设置项控制「是否注册点外部关闭监听器」，Pin 控制的是 autoDismiss 模式下的豁免。两者不冲突。
3. **不取消当前流**：Bug 2 修复采用「丢弃过期捕获」而非「新触发取消当前流」，避免用户误触热键打断正在生成的好结果。用户若想覆盖，可先 Esc 取消再触发，或用 Pin 后的命令面板。
4. **非模态横幅不阻塞**：原模态 alert 抢焦点且阻塞，是用户反馈「很难受」的体验来源之一。改为非模态横幅，3 秒自动消失，用户可继续操作。
5. **横幅不内嵌「打开快捷提问」按钮**：为避免在 ResultView 新增回调链（改动大），横幅仅提示文案 + 关闭。用户已有快捷键/菜单进入快捷提问。这与探索报告中「notifyNoSelection 的快捷提问按钮」是降级，但权衡改动复杂度后可接受。
6. **CodingKey 向后兼容**：新增 `resultPanelDismissMode` 缺键时解码为默认值 `.keepAfterResult`，老存档无破坏。
7. **导出清理**：导出配置时重置为默认值，不带本机窗口偏好（与 panelWidth/Height/iCloud 重置一致的模式）。
8. **范围严格限定**：不做 QuickInput 的 isStreaming 守卫、不做热键防抖、不做全面并发审查（用户选择「仅修复这两个明确 bug」）。

## Verification steps

1. **编译验证**：`swift build`（注：Linux 沙箱会因 `Carbon.HIToolbox`/`Darwin` 预存问题失败，需在 macOS 环境完整验证）；对改动文件做 `swiftc -parse` 语法检查。

2. **逻辑测试**：`bash scripts/run-logic-tests.sh` 确认 SnapAILogic 层无回归（本次改动主要在 SnapAI UI 层，但 Settings.swift 改动需确认编解码测试通过）。重点检查 `Tests/SnapAILogicTests/SettingsMigrationTests.swift` 中 panelWidth/Height 相关测试是否受影响（应不受影响，因新增独立 key）。

3. **Bug 1 手动验证**（macOS 环境）：
   - 默认 `.keepAfterResult` 模式：触发动作 → 结果生成中点击其他窗口 → 浮窗不消失；生成完成 → 点击其他窗口 → 浮窗不消失；按 Esc → 浮窗关闭；点 X → 浮窗关闭。
   - 切到 `.autoDismiss`：恢复旧行为，点外部即关（除非 Pin）。
   - 切到 `.alwaysKeep`：点外部永不关，仅 Esc/X/写回关闭。
   - 设置项改动后浮窗行为即时生效（下次 `show()` 装/拆监听器）。

4. **Bug 2 手动验证**（macOS 环境）：
   - 触发动作 A，结果生成中再次按热键触发动作 A → 不再弹「未检测到选中文字」模态框；旧捕获回调被代际令牌丢弃。
   - 触发动作但未选中文本 → 结果窗口显示非模态横幅「未检测到选中的文字」，3 秒自动消失，不阻塞。
   - 检查菜单「上次取词状态」未被过期捕获污染（代际令牌保证 `recordTextCaptureOutcome` 仅最新捕获生效）。

5. **回归检查**：
   - 写回替换原文后浮窗仍正常关闭（`AppDelegate+WriteBack.swift:28` 的 `panelController.hide()` 不受影响）。
   - Pin 按钮在 autoDismiss 模式下仍正常豁免点外部关闭。
   - 设置项导入导出：导出配置 JSON 不含本机 `resultPanelDismissMode` 偏好（被重置为默认）；导入老配置（无该 key）解码为默认值不崩溃。

## 涉及文件清单

| 文件 | 改动类型 |
|---|---|
| `Sources/SnapAI/Settings.swift` | 新增枚举 + @Published + CodingKey + decode/encode |
| `Sources/SnapAI/AppSettingsImportSanitization.swift` | 导出时重置新字段 |
| `Sources/SnapAI/FloatingPanel.swift` | installDismissMonitors 按 mode 决定是否注册全局监听器 |
| `Sources/SnapAI/GeneralSettingsSection.swift` | 新增 resultPanelDismissRow Picker |
| `Sources/SnapAI/AppDelegate.swift` | captureGeneration 令牌 + triggerCapturedSelection 守卫 + showNoSelectionNotice 非模态 |
| `Sources/SnapAI/ResultViewModel.swift` | 新增 transientNotice 状态与方法 |
| `Sources/SnapAI/ResultView.swift` | 挂载非模态横幅 |
| `Sources/SnapAI/SnapAIUI.swift` | 新增 SnapAITransientNoticeBanner 视图 |
