# SnapAI 1.6.53

SnapAI 1.6.53 继续落实全量审计中的 target 边界与冗余代码治理。本版删除 app/logic 两端重复编译的写回命令定义,并让 AppKit 菜单只保留 UI adapter 职责。

## 重构

- `WriteBackCommand` 从 symlink 迁移为 `SnapAILogic` 真实源码。
- 新增 `WriteBackCommandInput` 和 `WriteBackCommandOperation`,library factory 不再依赖 app-local `TextWriteBackRecord` / `TextWriteBackOperation`。
- app target 新增 `WriteBackCommandAppBridge`,负责将写回记录转换为纯 DTO。
- 删除 `Sources/SnapAI/WriteBackCommand.swift`,命令 descriptor 只保留一份 source of truth。
- `MenuCoordinator` 从 `SnapAILogic` manifest 移除,避免 AppKit UI 在 app 和 library 中重复编译。
- 模型切换菜单改为消费 `ModelSwitchCommandFactory` descriptor,与命令面板共享启用状态、模型过滤、标题脱敏和当前模型判断。
- 删除 logic suite 中直接构造 `NSMenu` 的 UI 测试,改由纯 descriptor 测试覆盖无模型和禁用供应商逻辑。

## 边界基线

- `SnapAILogic` symlink:39 个,由 41 个下降 2 个。
- `SnapAILogic` 真实源码:37 个,由 36 个增加 1 个。
- remediation gate 禁止 `MenuCoordinator` 再进入 logic target,并禁止 `WriteBackCommand` 回退为 symlink 或 app 重复源码。

## 验证

- `scripts/run-audit-remediation-check.sh`
- `scripts/run-logic-tests.sh`
- `swift build`
- `scripts/run-macos-smoke-tests.sh --skip-logic`
- `scripts/preflight-release.sh`

## Release 资产

- `SnapAI-v1.6.53.zip`
- `snapai-manifest-v1.6.53.json`
- `snapai-manifest-v1.6.53.json.sig`
- `snapai-sbom-v1.6.53.json`
