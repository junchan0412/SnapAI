# SnapAI 1.6.26

SnapAI 1.6.26 继续推进 `SnapAILogic` target 的真实源码迁移。本版将截图权限、截图临时文件和截图失败诊断逻辑移入 library target。

## 改进

- `ScreenCapturePermission` 移入 `Sources/SnapAILogic` 实体源码,并从 app target 删除同名文件。
- `ScreenCaptureTemporaryFile` 移入 `Sources/SnapAILogic` 实体源码,并从 app target 删除同名文件。
- `ScreenCaptureFailureDiagnostic` 移入 `Sources/SnapAILogic` 实体源码,并从 app target 删除同名文件。
- `QuickInput` 显式 `import SnapAILogic`,使用已迁移的截图诊断类型。
- `scripts/run-audit-remediation-check.sh` 新增截图诊断迁移防回退检查。
- `SnapAILogic` 当前为 7 个实体 Swift 源文件 + 69 个剩余 symlink。

## 发布资产

- `SnapAI-v1.6.26.zip`
- `snapai-manifest-v1.6.26.json`
- `snapai-manifest-v1.6.26.json.sig`
- `snapai-sbom-v1.6.26.json`
