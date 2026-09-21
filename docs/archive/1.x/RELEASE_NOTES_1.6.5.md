# SnapAI 1.6.5

SnapAI 1.6.5 是一次工程质量与发布门禁升级版本,重点完成标准 SwiftPM 测试目标、GitHub Actions CI 以及核心模块拆分。

## 主要更新

- 新增 `SnapAILogic` library target 和 `SnapAILogicTests` test target,核心逻辑现在可以被 SwiftPM、IDE 和 CI 标准发现。
- `scripts/run-logic-tests.sh` 改为兼容包装:有 XCTest 的环境运行 `swift test`,仅安装 Command Line Tools 且缺 XCTest 的环境自动回退到本地 `swiftc` runner。
- 新增 `.github/workflows/ci.yml`,远端门禁覆盖 `git diff --check`、`swift build`、`swift test` 和逻辑测试包装脚本。
- 拆分 `AppDelegate` 中的自动化 URL、Services 捕获、写回、诊断、结果命令和命令面板职责。
- 拆分 `AIRequestRouter` 的路由诊断结构到 `RoutingDiagnostics.swift`,让候选路由排序逻辑更集中。
- 拆分 `AppSettings` 持久化读写到 `SettingsPersistence.swift`。
- 拆分设置页支持状态与 sidebar row 到 `SettingsViewSupport.swift`。

## 验证

- `./scripts/run-logic-tests.sh`
- `swift build`
- `scripts/preflight-release.sh`

