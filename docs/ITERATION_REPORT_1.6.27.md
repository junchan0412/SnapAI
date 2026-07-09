# SnapAI 1.6.27 迭代报告

## 背景

此前版本已迁移结果路由文案、文本 diff、追问输入/历史和截图诊断簇。本轮继续处理低耦合的流式输出状态机与系统权限恢复文案。

## 本轮目标

- 迁移 `StreamingAccumulator`,把流式输出和 `<think>` 分离逻辑沉到 `SnapAILogic`。
- 迁移系统隐私设置 URL 与取词失败恢复提示,让权限恢复文案也进入 library target。
- 继续降低 app target 与逻辑 target 的 symlink 镜像面。

## 实现摘要

- `StreamingAccumulator`、`SystemPrivacySettings`、`TextCaptureRecoveryGuide` 迁移为 `SnapAILogic` 实体源码。
- 相关 UI 文件显式导入 `SnapAILogic`。
- 审计修复 gate 新增这三块文件的实体源码和 app target 去重检查。

## 验证

- `scripts/check-logic-symlinks.sh`
- `scripts/run-audit-remediation-check.sh`
- `scripts/run-logic-tests.sh`
- `swift build`

## 剩余风险

当前仍有 66 个 symlink。后续迁移将逐渐接触更多被 `ResultCommand`、`AIRequestRouter`、`Settings` 和历史模块共同依赖的类型,需要继续以依赖簇为单位移动,并谨慎调整 public API。
