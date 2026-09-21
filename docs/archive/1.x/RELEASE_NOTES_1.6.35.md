# SnapAI 1.6.35

SnapAI 1.6.35 继续推进审计报告中的 `SnapAILogic` target 收敛问题。本版新增迁移候选分析脚本,把剩余 symlink 的跨文件消费者关系显式化,为下一轮按簇迁移提供可靠依据。

## 改进

- 新增 `scripts/report-logic-migration-candidates.sh`,列出每个剩余 symlink 是否仍被其它 symlink 消费。
- `scripts/run-audit-remediation-check.sh` 会检查该脚本可执行并成功运行。
- `docs/LOGIC_TARGET_MIGRATION_PLAN.md` 补充候选分析说明。
- README 更新到 1.6.35。

## 验证

- `scripts/check-logic-symlinks.sh`
- `scripts/report-logic-migration-candidates.sh`
- `scripts/run-audit-remediation-check.sh`
- `scripts/run-logic-tests.sh`
- `swift build`
- `scripts/preflight-release.sh`

## Release 资产

- `SnapAI-v1.6.35.zip`
- `snapai-manifest-v1.6.35.json`
- `snapai-manifest-v1.6.35.json.sig`
- `snapai-sbom-v1.6.35.json`
