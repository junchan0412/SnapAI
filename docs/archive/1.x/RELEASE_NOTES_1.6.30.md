# SnapAI 1.6.30

SnapAI 1.6.30 继续推进 `SnapAILogic` target 的真实源码迁移。本版迁移结果写回协调器,让替换、追加和自动替换判定由逻辑 target 统一提供。

## 改进

- `ResultWriteBackCoordinator` 已成为 `SnapAILogic` 的真实 public 源码。
- 结果面板继续通过同一套逻辑 API 执行替换、追加和自动替换判定。
- 审计修复 gate 增加结果写回协调器防回退检查。

## 验证

- `scripts/check-logic-symlinks.sh`
- `scripts/run-audit-remediation-check.sh`
- `scripts/run-logic-tests.sh`
- `swift build`
- `scripts/preflight-release.sh`

## Release 资产

- `SnapAI-v1.6.30.zip`
- `snapai-manifest-v1.6.30.json`
- `snapai-manifest-v1.6.30.json.sig`
- `snapai-sbom-v1.6.30.json`
