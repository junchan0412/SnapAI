# SnapAI 1.6.50

SnapAI 1.6.50 继续收敛审计报告中的 `SnapAILogic` symlink 镜像问题。本版迁移自动化 URL 命令解析主体,让 URL parse 结果成为 logic target 的真实值对象。

## 改进

- `AutomationURLCommand.swift` 已从 `Sources/SnapAI` 迁移到 `Sources/SnapAILogic` 真实源码。
- `AutomationRunOptions`, `AutomationHistoryContextOptions` 和 `AutomationURLCommand.parse(_:)` 作为跨 target 自动化 URL 边界公开。
- 新增 `AutomationURLCommandAppBridge`,将 `AppSettings` / `AIAction` 相关的模型、上下文、动作、设置 section 和写回策略选择保留在 app target。
- app handler 对 history criteria、路由偏好、工作模式和打字机速度做显式跨 target 转换,避免同名类型被误用。
- `scripts/check-logic-symlinks.sh` 基线收紧为最多 42 个 symlink、至少 34 个真实源码。
- 审计门禁新增 `AutomationURLCommand` 与 app bridge 防回退检查。

## 验证

- `scripts/check-logic-symlinks.sh`
- `scripts/report-logic-migration-candidates.sh`
- `scripts/run-audit-remediation-check.sh`
- `scripts/run-logic-tests.sh`
- `swift build`
- `scripts/preflight-release.sh`

## Release 资产

- `SnapAI-v1.6.50.zip`
- `snapai-manifest-v1.6.50.json`
- `snapai-manifest-v1.6.50.json.sig`
- `snapai-sbom-v1.6.50.json`
