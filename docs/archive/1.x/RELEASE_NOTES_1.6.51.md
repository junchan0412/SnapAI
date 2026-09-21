# SnapAI 1.6.51

SnapAI 1.6.51 继续收敛审计报告中的 `SnapAILogic` symlink 镜像问题。本版迁移设置页 section 值对象,让设置导航元数据由 logic target 提供。

## 改进

- `SettingsSection.swift` 已从 `Sources/SnapAI` 迁移到 `Sources/SnapAILogic` 真实源码。
- `SettingsSection` 公开 `id`, `title`, `icon`, `subtitle`, `tabWidth`,供 app target 的设置页、窗口协调器和自动化桥接使用。
- `SettingsViewSupport` 显式导入 `SnapAILogic`,避免隐式依赖 app target 同名文件。
- `scripts/check-logic-symlinks.sh` 基线收紧为最多 41 个 symlink、至少 35 个真实源码。
- 审计门禁新增 `SettingsSection` 防回退检查。

## 验证

- `scripts/check-logic-symlinks.sh`
- `scripts/report-logic-migration-candidates.sh`
- `scripts/run-audit-remediation-check.sh`
- `scripts/run-logic-tests.sh`
- `swift build`
- `scripts/preflight-release.sh`

## Release 资产

- `SnapAI-v1.6.51.zip`
- `snapai-manifest-v1.6.51.json`
- `snapai-manifest-v1.6.51.json.sig`
- `snapai-sbom-v1.6.51.json`
