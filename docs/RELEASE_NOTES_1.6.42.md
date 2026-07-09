# SnapAI 1.6.42

SnapAI 1.6.42 继续收敛 `SnapAILogic` target 的 symlink 镜像。本版迁移历史导出命令描述器,并用轻量 DTO 解耦 app target 的历史记录模型与筛选条件。

## 改进

- `HistoryExportCommand.swift` 已从 `Sources/SnapAI` 迁移到 `Sources/SnapAILogic` 真实源码。
- 新增 `HistoryExportCommandInput` 与 `HistoryExportCommandCriteria`,避免 logic public API 暴露 `HistoryEntry` / `HistoryFilterCriteria`。
- 新增 `HistoryExportCommandAppBridge`,由 app target 负责把历史记录和导出 criteria 映射回现有执行路径。
- `scripts/check-logic-symlinks.sh` 基线收紧为最多 51 个 symlink、至少 25 个真实源码。
- 审计门禁新增 `HistoryExportCommand` 防回退检查。

## 验证

- `scripts/check-logic-symlinks.sh`
- `scripts/report-logic-migration-candidates.sh`
- `scripts/run-audit-remediation-check.sh`
- `scripts/run-logic-tests.sh`
- `swift build`
- `scripts/preflight-release.sh`

## Release 资产

- `SnapAI-v1.6.42.zip`
- `snapai-manifest-v1.6.42.json`
- `snapai-manifest-v1.6.42.json.sig`
- `snapai-sbom-v1.6.42.json`
