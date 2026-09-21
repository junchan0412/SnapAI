# SnapAI 1.6.36

SnapAI 1.6.36 继续收敛审计报告中的 `SnapAILogic` symlink 镜像问题。本版迁移动作命令面板描述器,并用轻量 DTO 隔离 app 设置模型与 logic target。

## 改进

- `ActionCommand.swift` 已从 `Sources/SnapAI` 迁移到 `Sources/SnapAILogic` 真实源码。
- 新增 `ActionCommandInput`,让命令面板 factory 不再公开接收 `AIAction`。
- `AppDelegate+CommandPalette` 在 app target 内把 `AIAction` 映射为轻量输入。
- `scripts/check-logic-symlinks.sh` 基线收紧为最多 57 个 symlink、至少 19 个真实源码。
- 审计门禁新增 `ActionCommand` 防回退检查。

## 验证

- `scripts/check-logic-symlinks.sh`
- `scripts/report-logic-migration-candidates.sh`
- `scripts/run-audit-remediation-check.sh`
- `scripts/run-logic-tests.sh`
- `swift build`
- `scripts/preflight-release.sh`

## Release 资产

- `SnapAI-v1.6.36.zip`
- `snapai-manifest-v1.6.36.json`
- `snapai-manifest-v1.6.36.json.sig`
- `snapai-sbom-v1.6.36.json`
