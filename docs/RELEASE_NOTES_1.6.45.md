# SnapAI 1.6.45

SnapAI 1.6.45 继续推进 `SnapAILogic` 真实源码迁移。本版迁移命令 ID slug 与去重工具,让命令面板、动作模板库和后续自动化命令共享同一套 logic API。

## 改进

- `CommandIdentifier.swift` 已从 `Sources/SnapAI` 迁移到 `Sources/SnapAILogic` 真实源码。
- `CommandIdentifier` API 公开化,供 app target 通过 `SnapAILogic` 调用。
- `scripts/check-logic-symlinks.sh` 基线收紧为最多 48 个 symlink、至少 28 个真实源码。
- 审计门禁新增 `CommandIdentifier` 防回退检查。

## 验证

- `scripts/check-logic-symlinks.sh`
- `scripts/report-logic-migration-candidates.sh`
- `scripts/run-audit-remediation-check.sh`
- `scripts/run-logic-tests.sh`
- `swift build`
- `scripts/preflight-release.sh`

## Release 资产

- `SnapAI-v1.6.45.zip`
- `snapai-manifest-v1.6.45.json`
- `snapai-manifest-v1.6.45.json.sig`
- `snapai-sbom-v1.6.45.json`
