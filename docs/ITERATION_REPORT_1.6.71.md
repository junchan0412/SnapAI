# SnapAI 1.6.71 迭代报告

## 问题证据

1.6.70 之后远端合入了两批用户可见改动:界面与人机交互统一,以及两个明确交互 bug。结果浮窗此前默认在点击外部时关闭,用户生成长回答时很容易误触丢失。异步文本捕获没有代际守卫,旧的空选回调仍可能弹出模态 alert,并在结果已经开始生成时打断用户。

同时,多个设置页、结果页、历史与快捷提问面板的控件样式与反馈路径仍有局部差异。若直接按代码提交顺序分别发版,用户会连续收到两次安装更新;因此本版把这些未发布改动收口为 1.6.71 正式 release。

## 失焦策略边界

`ResultPanelDismissMode` 成为窗口关闭策略的唯一配置入口。`FloatingPanelController` 只在 `autoDismiss` 模式下注册全局鼠标监听器;`keepAfterResult` 与 `alwaysKeep` 依赖 Esc、关闭按钮或写回关闭。默认值切到 `keepAfterResult`,直接降低误关成本,同时保留旧行为可选项。

导出配置时会把该偏好重置为默认值,避免把本机窗口习惯同步到其他设备。

## 空选提示与捕获代际

`AppDelegate` 用 `captureGeneration` 标记每一次文本捕获。回调开头若发现代际过期或当前结果已在流式生成,直接丢弃,不再记录诊断或展示提示。真正的空选路径改为 `showTransientNotice`,由结果窗口显示非模态横幅,3 秒自动消失,也可手动关闭。

这消除了阻塞式 `NSAlert.runModal()` 抢焦点的问题,也避免过期捕获把「上次取词状态」写脏。

## UI 收口

PR #20 的共享 UI 与控件交互更新覆盖设置、结果、历史、快捷提问、权限健康、快捷键录制等表面。本版不额外做大范围行为变更,目标是让已合入的交互一致性进入正式签名包,并与 1.6.70 已建立的 operation feedback 通道兼容。

## 回归保护

- 版本号 `CFBundleShortVersionString` / `CFBundleVersion` 对齐为 1.6.71。
- release preflight 继续覆盖 logic tests、macOS smoke、稳定签名、manifest 签名、SBOM 与 zip 解包验证。
- 自动更新 manifest 继续绑定既有 codesign 指纹,不更换签名身份。

本轮没有向第三方 provider 发送真实用户内容。性能结论限定为删除阻塞式空选 alert、减少误关结果窗口,以及避免过期捕获回调干扰生成中的结果;不声明未测量的延迟或内存百分比。
