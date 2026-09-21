# SnapAI 1.6.27

SnapAI 1.6.27 继续推进 `SnapAILogic` target 的真实源码迁移。本版迁移流式输出累积器、系统隐私设置 URL 和取词失败恢复提示。

## 改进

- `StreamingAccumulator` 移入 `Sources/SnapAILogic` 实体源码,并从 app target 删除同名文件。
- `SystemPrivacySettings` 移入 `Sources/SnapAILogic` 实体源码,并从 app target 删除同名文件。
- `TextCaptureRecoveryGuide` 移入 `Sources/SnapAILogic` 实体源码,并从 app target 删除同名文件。
- `AppDelegate`、`OnboardingView`、`PermissionSettingsSection` 和 `PermissionHealthView` 显式 `import SnapAILogic`。
- `scripts/run-audit-remediation-check.sh` 新增这三块迁移防回退检查。
- `SnapAILogic` 当前为 10 个实体 Swift 源文件 + 66 个剩余 symlink。

## 发布资产

- `SnapAI-v1.6.27.zip`
- `snapai-manifest-v1.6.27.json`
- `snapai-manifest-v1.6.27.json.sig`
- `snapai-sbom-v1.6.27.json`
