# SnapAI 1.6.46

SnapAI 1.6.46 继续收敛 `SnapAILogic` target 的 symlink 镜像。本版迁移安装日志命令字幕逻辑,并用轻量状态 DTO 解耦更新器内部状态。

## 改进

- `InstallLogCommand.swift` 已从 `Sources/SnapAI` 迁移到 `Sources/SnapAILogic` 真实源码。
- 新增 `InstallLogCommandStatus`,让 logic public API 不再暴露 `UpdateChecker.InstallLogStatus`。
- 新增 `InstallLogCommandAppBridge`,由 app target 将更新器状态映射为命令状态。
- 安装日志路径脱敏逻辑由 `InstallLogCommand` 自身提供,继续隐藏 `/Users/<name>` 中的用户名。
- `scripts/check-logic-symlinks.sh` 基线收紧为最多 47 个 symlink、至少 29 个真实源码。
- 审计门禁新增 `InstallLogCommand` 防回退检查。

## 验证

- `scripts/check-logic-symlinks.sh`
- `scripts/report-logic-migration-candidates.sh`
- `scripts/run-audit-remediation-check.sh`
- `scripts/run-logic-tests.sh`
- `swift build`
- `scripts/preflight-release.sh`

## Release 资产

- `SnapAI-v1.6.46.zip`
- `snapai-manifest-v1.6.46.json`
- `snapai-manifest-v1.6.46.json.sig`
- `snapai-sbom-v1.6.46.json`
