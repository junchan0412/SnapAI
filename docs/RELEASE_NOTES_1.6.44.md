# SnapAI 1.6.44

SnapAI 1.6.44 完成命令描述器小簇中的动作模板库迁移。本版将内置动作模板、动作库导入导出和安装去重逻辑移入 `SnapAILogic`,并通过轻量 DTO 保持 app target 的 `AIAction` 边界清晰。

## 改进

- `ActionTemplateLibrary.swift` 已从 `Sources/SnapAI` 迁移到 `Sources/SnapAILogic` 真实源码。
- 新增 `ActionTemplateAction`,用于描述可分享动作模板,避免 logic public API 暴露 `AIAction`。
- 新增 `ActionTemplateLibraryAppBridge`,由 app target 负责 `AIAction` 与模板 DTO 的双向转换。
- 动作库导出继续移除 hotkey、provider id 和 model override 等本机私有字段。
- `scripts/check-logic-symlinks.sh` 基线收紧为最多 49 个 symlink、至少 27 个真实源码。
- 审计门禁新增 `ActionTemplateLibrary` 防回退检查。

## 验证

- `scripts/check-logic-symlinks.sh`
- `scripts/report-logic-migration-candidates.sh`
- `scripts/run-audit-remediation-check.sh`
- `scripts/run-logic-tests.sh`
- `swift build`
- `scripts/preflight-release.sh`

## Release 资产

- `SnapAI-v1.6.44.zip`
- `snapai-manifest-v1.6.44.json`
- `snapai-manifest-v1.6.44.json.sig`
- `snapai-sbom-v1.6.44.json`
