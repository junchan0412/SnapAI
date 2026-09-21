# SnapAI 1.6.38

SnapAI 1.6.38 继续收敛 `SnapAILogic` target 的 symlink 镜像。本版迁移工作模式命令描述器,并用轻量 DTO 解耦 app target 的 `WorkModePreset`。

## 改进

- `WorkModeCommand.swift` 已从 `Sources/SnapAI` 迁移到 `Sources/SnapAILogic` 真实源码。
- 新增 `WorkModeCommandInput`,让工作模式命令 factory 不再公开接收 `WorkModePreset`。
- `AppDelegate+CommandPalette` 在 app target 内完成 mode id 与 `WorkModePreset` 的映射。
- `scripts/check-logic-symlinks.sh` 基线收紧为最多 55 个 symlink、至少 21 个真实源码。
- 审计门禁新增 `WorkModeCommand` 防回退检查。

## 验证

- `scripts/check-logic-symlinks.sh`
- `scripts/report-logic-migration-candidates.sh`
- `scripts/run-audit-remediation-check.sh`
- `scripts/run-logic-tests.sh`
- `swift build`
- `scripts/preflight-release.sh`

## Release 资产

- `SnapAI-v1.6.38.zip`
- `snapai-manifest-v1.6.38.json`
- `snapai-manifest-v1.6.38.json.sig`
- `snapai-sbom-v1.6.38.json`
