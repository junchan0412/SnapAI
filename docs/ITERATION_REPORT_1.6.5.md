# SnapAI 1.6.5 迭代报告

1.6.5 聚焦工程可维护性、远端门禁和发版可信度。此前核心逻辑测试依赖手写 `swiftc` 文件清单,大型模块也集中承载过多职责;本轮将测试、CI 和模块边界做成更长期可演进的形态。

## 已完成

- 在 `Package.swift` 中新增 `SnapAILogic` library target 和 `SnapAILogicTests` test target。
- 将旧逻辑测试入口封装为 XCTest runner;在缺少 XCTest 的本机 Command Line Tools 环境中,测试脚本会自动回退到兼容 runner。
- 新增 GitHub Actions CI,覆盖 SwiftPM 构建、标准测试、兼容测试脚本和空白 diff 检查。
- 将 `AppDelegate` 拆分为自动化命令、Services 捕获、写回、诊断、结果命令和命令面板等 extension 文件。
- 将 `AIRequestRouter` 中的诊断模型与摘要逻辑拆到 `RoutingDiagnostics.swift`。
- 将设置持久化读写拆到 `SettingsPersistence.swift`。
- 将设置页支持状态对象和 sidebar row 拆到 `SettingsViewSupport.swift`。
- 更新 README、UI 总览图、Release Notes 和 Iteration Report 到 1.6.5。

## 验证

- 逻辑测试通过。
- SwiftPM 构建通过。
- Release 预检通过。

## 发布资产

完整 release 包应包含:

- `SnapAI-v1.6.5.zip`
- `snapai-manifest-v1.6.5.json`
- `snapai-manifest-v1.6.5.json.sig`

