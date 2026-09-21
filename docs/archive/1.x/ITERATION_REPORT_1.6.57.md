# SnapAI 1.6.57 迭代报告

## 背景

`UpdateChecker.swift` 达到 1092 行,同时承担十余项职责。为了让 manifest、digest 和版本规则进入 logic tests,整份含 AppKit 的文件长期以 symlink 进入 `SnapAILogic`,造成重复编译和边界倒置。

## 拆分结果

### UpdateChecker core

- Release、Asset、ReleaseManifest 和 UpdateError 数据模型。
- asset 选择、版本比较、digest/manifest/signature 验证。
- 流式 SHA256 文件计算,不会一次性把更新包读入内存。
- designated requirement 解析和安装日志路径安全检查。

### UpdateCheckerApp adapter

- GitHub API 与网页 fallback 请求。
- NSAlert 展示与用户选择。
- 更新包下载、解压和 codesign 连续性检查。
- bundled updater / shell fallback 启动和应用退出。

## 诊断解耦

`Diagnostics.swift` 原本在构建权限健康快照时直接读取 `UpdateChecker.latestInstallLogStatus()`。这使纯诊断逻辑依赖更新器全局状态。现在快照只接收轻量 DTO,app bridge 决定何时读取 UserDefaults 和文件系统。

## 结果

- 1092 行混合文件拆为 620 + 479 行两个明确边界。
- symlink:37 → 36。
- 真实 logic source:39 → 40。
- logic suite、SwiftPM build、macOS smoke 和边界门禁通过。
