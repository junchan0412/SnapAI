# SnapAI 1.6.28

SnapAI 1.6.28 继续推进 `SnapAILogic` target 的真实源码迁移。本版迁移设置窗口置顶状态与命令文案,减少 app target 与逻辑测试 target 的文件镜像耦合。

## 改进

- `SettingsWindowPinState` 和 `SettingsWindowPinCommand` 已成为 `SnapAILogic` 的真实 public 源码。
- App 侧设置窗口与命令面板改为通过 `SnapAILogic` 使用置顶状态/文案/图标逻辑。
- 审计修复 gate 增加 `SettingsWindowPinCommand` 防回退检查。

## 验证

- `scripts/check-logic-symlinks.sh`
- `scripts/run-audit-remediation-check.sh`
- `scripts/run-logic-tests.sh`
- `swift build`
- `scripts/preflight-release.sh`

## Release 资产

- `SnapAI-v1.6.28.zip`
- `snapai-manifest-v1.6.28.json`
- `snapai-manifest-v1.6.28.json.sig`
- `snapai-sbom-v1.6.28.json`
