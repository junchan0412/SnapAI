# SnapAI 1.6.48

SnapAI 1.6.48 继续处理审计报告中的 `SnapAILogic` symlink 镜像问题。本版迁移结果持久化小簇,让完成指标和对话 Markdown 导出由 logic target 提供。

## 改进

- `ResultPersistence.swift` 已从 `Sources/SnapAI` 迁移到 `Sources/SnapAILogic` 真实源码。
- `ConversationExport.swift` 已从 `Sources/SnapAI` 迁移到 `Sources/SnapAILogic` 真实源码。
- 新增 `ResultPersistenceAppBridge`,将 `AppSettings` / `AIAction` / `AIRequestDiagnostics` 相关的历史保存和诊断映射保留在 app target。
- 对话导出继续保留隐私保护正文省略、诊断脱敏和 Markdown fence 安全处理。
- `scripts/check-logic-symlinks.sh` 基线收紧为最多 44 个 symlink、至少 32 个真实源码。
- 审计门禁新增 `ResultPersistence` 与 `ConversationExport` 防回退检查。

## 验证

- `scripts/check-logic-symlinks.sh`
- `scripts/report-logic-migration-candidates.sh`
- `scripts/run-audit-remediation-check.sh`
- `scripts/run-logic-tests.sh`
- `swift build`
- `scripts/preflight-release.sh`

## Release 资产

- `SnapAI-v1.6.48.zip`
- `snapai-manifest-v1.6.48.json`
- `snapai-manifest-v1.6.48.json.sig`
- `snapai-sbom-v1.6.48.json`
