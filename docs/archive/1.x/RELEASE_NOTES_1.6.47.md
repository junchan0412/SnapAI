# SnapAI 1.6.47

SnapAI 1.6.47 继续收敛 `SnapAILogic` target 的 symlink 镜像。本版迁移取词诊断摘要和恢复建议逻辑,并用轻量诊断枚举隔离取词实现细节。

## 改进

- `TextCaptureDiagnostic.swift` 已从 `Sources/SnapAI` 迁移到 `Sources/SnapAILogic` 真实源码。
- 新增 `TextCaptureDiagnosticMethod` 与 `TextCaptureDiagnosticFailureReason`,避免 logic public API 暴露 `TextCaptureMethod` / `TextCaptureFailureReason`。
- 新增 `TextCaptureDiagnosticAppBridge`,由 app target 将取词结果映射为诊断状态。
- 取词诊断继续隐藏前台应用名称中的敏感信息,并保留剪贴板保护、辅助功能缺失和复制兜底失败的恢复建议。
- `scripts/check-logic-symlinks.sh` 基线收紧为最多 46 个 symlink、至少 30 个真实源码。
- 审计门禁新增 `TextCaptureDiagnostic` 防回退检查。

## 验证

- `scripts/check-logic-symlinks.sh`
- `scripts/report-logic-migration-candidates.sh`
- `scripts/run-audit-remediation-check.sh`
- `scripts/run-logic-tests.sh`
- `swift build`
- `scripts/preflight-release.sh`

## Release 资产

- `SnapAI-v1.6.47.zip`
- `snapai-manifest-v1.6.47.json`
- `snapai-manifest-v1.6.47.json.sig`
- `snapai-sbom-v1.6.47.json`
