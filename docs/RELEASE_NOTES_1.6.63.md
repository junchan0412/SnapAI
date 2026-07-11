# SnapAI 1.6.63

SnapAI 1.6.63 聚焦 `ResultViewModel` 的完成职责拆分。此前完成指标、usage 记录、历史保存、settings persistence 和自动替换全部集中在 VM 内,并依赖 `startTime`、`savedToHistory`、`metricsFinished` 三个私有标志维护一次性语义。

## Completion coordinator

- 新增 app 层 `ResultCompletionCoordinator`。
- coordinator 持有 completion state、route start time 和 lifecycle。
- 统一执行指标发布、动作使用统计、历史保存、设置落盘和自动写回。
- `ResultViewModel` 只负责构造当前 completion context 并消费 outcome。
- 自动写回发生后通过 outcome 清理 VM 的 auto-replace 标志。

## Lifecycle 一致性

- 新增真实 logic source `ResultCompletionLifecycle.swift`。
- 首次 `beginCompletion()` 成功,同一请求的重复调用被拒绝。
- `isHistorySaved` 在一次 lifecycle 内保持单调,后续 false 不会覆盖已保存状态。
- `reset()` 同时清除 completion 和 history guard。
- fallback route 重新标记计时起点,重试、重新生成和追问沿用统一 reset 路径。

## 清理与架构

- 从 `ResultViewModel` 删除 `startTime`、`savedToHistory` 和 `metricsFinished`。
- 从 VM 删除直接 history persistence、usage persistence 和 auto-replace side-effect 代码。
- `ResultViewModel` 从 716 行降至 691 行。
- remediation gate 将 VM 上限固定为 700 行,coordinator 上限为 130 行。
- `SnapAILogic` 当前为 44 个真实源码、36 个 symlink。

## 测试与验证

- lifecycle 测试覆盖首次完成、重复完成拒绝、history 状态单调与 reset 后复用。
- remediation gate 禁止完成标志或历史保存逻辑回流 VM。
- logic suite、SwiftPM build、macOS smoke 与签名 preflight 通过。

## Release 资产

- `SnapAI-v1.6.63.zip`
- `snapai-manifest-v1.6.63.json`
- `snapai-manifest-v1.6.63.json.sig`
- `snapai-sbom-v1.6.63.json`
