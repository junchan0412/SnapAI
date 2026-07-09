# SnapAI 1.6.29

SnapAI 1.6.29 继续推进 `SnapAILogic` target 的真实源码迁移。本版迁移结果面板命令簇,让结果操作、诊断、恢复建议和固定窗口命令由逻辑 target 提供。

## 改进

- `ResultCommand`, `ResultPinCommand`, `ResultDiagnosticsCommand` 和 `ResultRecoveryCommand` 已成为 `SnapAILogic` 的真实 public 源码。
- App 侧结果菜单、结果面板和命令面板通过 `SnapAILogic` 共享同一套命令描述与快捷键逻辑。
- 审计修复 gate 增加结果命令簇防回退检查。

## 验证

- `scripts/check-logic-symlinks.sh`
- `scripts/run-audit-remediation-check.sh`
- `scripts/run-logic-tests.sh`
- `swift build`
- `scripts/preflight-release.sh`

## Release 资产

- `SnapAI-v1.6.29.zip`
- `snapai-manifest-v1.6.29.json`
- `snapai-manifest-v1.6.29.json.sig`
- `snapai-sbom-v1.6.29.json`
