# SnapAI 1.6.40

SnapAI 1.6.40 继续收敛 `SnapAILogic` target 的 symlink 镜像。本版迁移模型切换命令描述器,并用轻量 DTO 解耦 app target 的 `AIProvider`。

## 改进

- `ModelSwitchCommand.swift` 已从 `Sources/SnapAI` 迁移到 `Sources/SnapAILogic` 真实源码。
- 新增 `ModelSwitchProviderInput`,让模型切换命令 factory 不再公开接收 `AIProvider`。
- `AppDelegate+CommandPalette` 在 app target 内将 `AIProvider` 映射为轻量输入。
- `scripts/check-logic-symlinks.sh` 基线收紧为最多 53 个 symlink、至少 23 个真实源码。
- 审计门禁新增 `ModelSwitchCommand` 防回退检查。

## 验证

- `scripts/check-logic-symlinks.sh`
- `scripts/report-logic-migration-candidates.sh`
- `scripts/run-audit-remediation-check.sh`
- `scripts/run-logic-tests.sh`
- `swift build`
- `scripts/preflight-release.sh`

## Release 资产

- `SnapAI-v1.6.40.zip`
- `snapai-manifest-v1.6.40.json`
- `snapai-manifest-v1.6.40.json.sig`
- `snapai-sbom-v1.6.40.json`
