# SnapAI 1.6.56

SnapAI 1.6.56 聚焦窗口生命周期与可复现内存测量。设置和 onboarding 窗口关闭后不再长期保留完整 SwiftUI hierarchy,同时避免 AppKit 自动 release 与 ARC 所有权冲突。

## 内存与生命周期

- `WindowCoordinator` 现在实现 `NSWindowDelegate`,统一处理设置与 onboarding 窗口关闭事件。
- 关闭完成后异步清空 `contentViewController`,释放 hosting controller 和 SwiftUI 视图树。
- 保留轻量 `NSWindow` shell,重新打开时延迟重建内容,同时保留 section、pin state 和 settings 状态。
- onboarding 正常完成和用户手动关闭共用同一内容释放路径。
- 禁止 `isReleasedWhenClosed = true`,避免 Accessibility 关闭动作触发 Objective-C autorelease 双重释放。

## 性能工具

- 新增 `scripts/profile-runtime-memory.sh`。
- 输出 RSS、CPU、physical footprint、peak footprint 和重点 VM region。
- 新增 [运行时内存基线](RUNTIME_MEMORY_BASELINE.md),记录测量方法、1.6.55 基线和后续场景。

## 回归保护

- macOS smoke 新增 reusable window content release probe。
- remediation gate 要求窗口关闭处理、延迟内容重建和内存 profiling 脚本持续存在。
- gate 禁止重新启用不安全的 AppKit 自动 release。

## 验证

- `scripts/run-audit-remediation-check.sh`
- `scripts/run-logic-tests.sh`
- `swift build`
- `scripts/run-macos-smoke-tests.sh --skip-logic`
- `scripts/profile-runtime-memory.sh SnapAI settings-open`
- `scripts/preflight-release.sh`

## Release 资产

- `SnapAI-v1.6.56.zip`
- `snapai-manifest-v1.6.56.json`
- `snapai-manifest-v1.6.56.json.sig`
- `snapai-sbom-v1.6.56.json`
