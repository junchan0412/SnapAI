# SnapAI 1.6.26 迭代报告

## 背景

1.6.24 和 1.6.25 已完成结果路由文案、文本 diff、追问输入和追问历史的实体迁移。本轮继续选择一个低耦合依赖簇:截图权限、临时文件命名和失败诊断。

## 本轮目标

- 将截图诊断相关纯逻辑移入 `SnapAILogic`。
- 保持 `QuickInput` UI 只消费 public library API。
- 继续降低 symlink 镜像面。

## 实现摘要

- `ScreenCapturePermission`、`ScreenCaptureTemporaryFile`、`ScreenCaptureFailureDiagnostic` 迁移为 `SnapAILogic` 实体源码。
- `QuickInput` 新增 `import SnapAILogic`。
- 审计修复 gate 新增三个截图相关文件的实体源码和 app target 去重检查。

## 验证

- `scripts/check-logic-symlinks.sh`
- `scripts/run-audit-remediation-check.sh`
- `scripts/run-logic-tests.sh`
- `swift build`

## 剩余风险

当前仍有 69 个 symlink。后续应继续以依赖簇为单位迁移,尤其避免单独迁移被共享文件依赖的底层类型。更高耦合模块迁移前需要先梳理访问级别和 import 边界。
