# SnapAI 1.6.17 迭代报告

## 背景

审计报告指出 `SnapAILogic` 通过 symlink 镜像 app 源文件,边界容易漂移。1.6.9 已新增 symlink manifest,但它只能确认“文件列表是否被显式更新”,不能阻止 UI-only 文件被有意或无意加入 manifest。

## 本轮目标

- 在 manifest 校验之外加入 UI-only 文件拒绝规则。
- 阻止 SwiftUI/WebKit/PDFKit 等 UI/渲染依赖进入逻辑 target。
- 保持当前 TextCapture、UpdateChecker 等确实需要 AppKit 的逻辑文件可继续测试。

## 实现摘要

- 更新 `scripts/check-logic-symlinks.sh`。
- 新增 `FORBIDDEN_FILE_PATTERNS`,覆盖 `*View.swift`、窗口/面板、设置 UI section、AppDelegate、QuickInput 等文件。
- 新增 `FORBIDDEN_IMPORTS`,覆盖 `SwiftUI`、`UniformTypeIdentifiers`、`WebKit`、`PDFKit`、`Quartz`。

## 验证

- `scripts/check-logic-symlinks.sh`
- 后续 release preflight 会继续覆盖逻辑测试、macOS smoke、app launch smoke、release build、签名、manifest 签名和 zip 校验。

## 剩余风险

这仍是 symlink 架构的防护栏,不是最终的真实 library target 迁移。后续可以逐步把纯逻辑文件实际移动到 `Sources/SnapAILogic`,让 app target 通过 `import SnapAILogic` 复用逻辑。
