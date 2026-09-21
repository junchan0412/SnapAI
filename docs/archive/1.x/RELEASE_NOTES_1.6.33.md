# SnapAI 1.6.33

SnapAI 1.6.33 为 `SnapAILogic` target 迁移加入硬性基线和后续拆分计划,防止已完成的真实源码迁移在后续迭代中回退。

## 改进

- `scripts/check-logic-symlinks.sh` 新增数量门禁:symlink 不得超过 58 个,真实源码不得少于 18 个。
- 新增 `docs/LOGIC_TARGET_MIGRATION_PLAN.md`,记录剩余迁移簇和依赖风险。
- README 更新到 1.6.33,并链接后续迁移计划。

## 验证

- `scripts/check-logic-symlinks.sh`
- `scripts/run-audit-remediation-check.sh`
- `scripts/run-logic-tests.sh`
- `swift build`
- `scripts/preflight-release.sh`

## Release 资产

- `SnapAI-v1.6.33.zip`
- `snapai-manifest-v1.6.33.json`
- `snapai-manifest-v1.6.33.json.sig`
- `snapai-sbom-v1.6.33.json`
