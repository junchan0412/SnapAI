# SnapAI 1.6.31

SnapAI 1.6.31 继续推进 `SnapAILogic` target 的真实源码迁移。本版迁移动作/模型/历史/设置搜索时使用的命令面板匹配逻辑。

## 改进

- `CommandPaletteMatcher` 已成为 `SnapAILogic` 的真实 public 源码。
- 命令面板 UI 通过 `SnapAILogic` 调用搜索匹配、排序和快捷键关键词扩展逻辑。
- 审计修复 gate 增加命令面板匹配器防回退检查。

## 验证

- `scripts/check-logic-symlinks.sh`
- `scripts/run-audit-remediation-check.sh`
- `scripts/run-logic-tests.sh`
- `swift build`
- `scripts/preflight-release.sh`

## Release 资产

- `SnapAI-v1.6.31.zip`
- `snapai-manifest-v1.6.31.json`
- `snapai-manifest-v1.6.31.json.sig`
- `snapai-sbom-v1.6.31.json`
