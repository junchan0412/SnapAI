# SnapAI 1.6.39

SnapAI 1.6.39 继续收敛 `SnapAILogic` target 的 symlink 镜像。本版迁移设置开关命令,并把 `AppSettings` 读写留在 app target 桥接扩展中。

## 改进

- `SettingsToggleCommand.swift` 已从 `Sources/SnapAI` 迁移到 `Sources/SnapAILogic` 真实源码。
- 新增 `SettingsToggleCommandState`,让 logic target 只处理开关解析、标题和纯状态变更。
- 新增 `SettingsToggleCommandAppSettings.swift`,由 app target 负责把命令应用到 `AppSettings`。
- `scripts/check-logic-symlinks.sh` 基线收紧为最多 54 个 symlink、至少 22 个真实源码。
- 审计门禁新增 `SettingsToggleCommand` 防回退和 app 桥接文件检查。

## 验证

- `scripts/check-logic-symlinks.sh`
- `scripts/report-logic-migration-candidates.sh`
- `scripts/run-audit-remediation-check.sh`
- `scripts/run-logic-tests.sh`
- `swift build`
- `scripts/preflight-release.sh`

## Release 资产

- `SnapAI-v1.6.39.zip`
- `snapai-manifest-v1.6.39.json`
- `snapai-manifest-v1.6.39.json.sig`
- `snapai-sbom-v1.6.39.json`
