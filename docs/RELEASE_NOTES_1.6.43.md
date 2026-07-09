# SnapAI 1.6.43

SnapAI 1.6.43 继续处理审计报告中的 `SnapAILogic` symlink 镜像问题。本版迁移历史上下文命令描述器,让“从历史创建上下文包”的命令面板入口由 logic target 提供。

## 改进

- `HistoryContextCommand.swift` 已从 `Sources/SnapAI` 迁移到 `Sources/SnapAILogic` 真实源码。
- 新增 `HistoryContextCommandInput` 与 `HistoryContextCommandCriteria`,避免 logic public API 暴露 `HistoryEntry` / `HistoryFilterCriteria`。
- App target 在桥接层中负责判断历史记录是否可作为上下文素材,logic target 只处理命令生成与 facet 排序。
- `scripts/check-logic-symlinks.sh` 基线收紧为最多 50 个 symlink、至少 26 个真实源码。
- 审计门禁新增 `HistoryContextCommand` 防回退检查。

## 验证

- `scripts/check-logic-symlinks.sh`
- `scripts/report-logic-migration-candidates.sh`
- `scripts/run-audit-remediation-check.sh`
- `scripts/run-logic-tests.sh`
- `swift build`
- `scripts/preflight-release.sh`

## Release 资产

- `SnapAI-v1.6.43.zip`
- `snapai-manifest-v1.6.43.json`
- `snapai-manifest-v1.6.43.json.sig`
- `snapai-sbom-v1.6.43.json`
