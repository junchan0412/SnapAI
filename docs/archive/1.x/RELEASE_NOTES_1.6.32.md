# SnapAI 1.6.32

SnapAI 1.6.32 继续推进 `SnapAILogic` target 的真实源码迁移。本版迁移取词目标解析器,让前台应用、最近外部应用和服务调用来源的选择规则由逻辑 target 提供。

## 改进

- `CaptureTargetResolver` 已成为 `SnapAILogic` 的真实 public 源码。
- App 侧取词目标选择继续使用同一套可测试规则。
- 审计修复 gate 增加取词目标解析器防回退检查。

## 验证

- `scripts/check-logic-symlinks.sh`
- `scripts/run-audit-remediation-check.sh`
- `scripts/run-logic-tests.sh`
- `swift build`
- `scripts/preflight-release.sh`

## Release 资产

- `SnapAI-v1.6.32.zip`
- `snapai-manifest-v1.6.32.json`
- `snapai-manifest-v1.6.32.json.sig`
- `snapai-sbom-v1.6.32.json`
