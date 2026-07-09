# SnapAI 1.6.41

SnapAI 1.6.41 继续收敛 `SnapAILogic` target 的 symlink 镜像。本版迁移路由/上下文命令描述器,并用轻量 DTO 解耦 app target 的路由偏好和上下文模型。

## 改进

- `RoutingContextCommand.swift` 已从 `Sources/SnapAI` 迁移到 `Sources/SnapAILogic` 真实源码。
- 新增 `RoutingPreferenceCommandInput` 与 `ContextProfileCommandInput`。
- `AppDelegate+CommandPalette` 在 app target 内将 `AIRoutingPreference` 和 `ContextProfile` 映射为轻量输入。
- `scripts/check-logic-symlinks.sh` 基线收紧为最多 52 个 symlink、至少 24 个真实源码。
- 审计门禁新增 `RoutingContextCommand` 防回退检查。

## 验证

- `scripts/check-logic-symlinks.sh`
- `scripts/report-logic-migration-candidates.sh`
- `scripts/run-audit-remediation-check.sh`
- `scripts/run-logic-tests.sh`
- `swift build`
- `scripts/preflight-release.sh`

## Release 资产

- `SnapAI-v1.6.41.zip`
- `snapai-manifest-v1.6.41.json`
- `snapai-manifest-v1.6.41.json.sig`
- `snapai-sbom-v1.6.41.json`
