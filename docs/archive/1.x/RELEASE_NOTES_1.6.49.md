# SnapAI 1.6.49

SnapAI 1.6.49 继续处理审计报告中的 `SnapAILogic` symlink 镜像问题。本版迁移自动化 URL 薄路由,减少 app target 与 logic target 之间的文件系统耦合。

## 改进

- `AutomationRouter.swift` 已从 `Sources/SnapAI` 迁移到 `Sources/SnapAILogic` 真实源码。
- app 侧自动化 URL handler 改为直接调用 `AutomationURLCommand.parse`,设置页 section 选择改为直接调用 `AutomationSettingsSectionSelection.resolve`。
- 本轮没有为 `AutomationURLCommand` / `SettingsSection` 额外扩大 public API,避免为薄包装迁移引入不必要的跨 target 暴露。
- `scripts/check-logic-symlinks.sh` 基线收紧为最多 43 个 symlink、至少 33 个真实源码。
- 审计门禁新增 `AutomationRouter` 防回退检查。

## 验证

- `scripts/check-logic-symlinks.sh`
- `scripts/report-logic-migration-candidates.sh`
- `scripts/run-audit-remediation-check.sh`
- `scripts/run-logic-tests.sh`
- `swift build`
- `scripts/preflight-release.sh`

## Release 资产

- `SnapAI-v1.6.49.zip`
- `snapai-manifest-v1.6.49.json`
- `snapai-manifest-v1.6.49.json.sig`
- `snapai-sbom-v1.6.49.json`
