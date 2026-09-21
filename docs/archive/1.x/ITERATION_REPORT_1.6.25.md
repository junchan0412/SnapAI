# SnapAI 1.6.25 迭代报告

## 背景

1.6.24 已验证渐进式实体迁移路径可行:app target 依赖 `SnapAILogic`,手工 `build.sh` 也能编译并链接 library module。本轮继续选择低耦合逻辑文件,减少 symlink 边界。

## 本轮目标

- 迁移追问输入行为与追问历史导航逻辑。
- 避免只迁单个文件导致仍在 app target 的共享文件需要自引用导入。
- 继续保持 SwiftPM build、手工 release build 和逻辑测试可通过。

## 实现摘要

- `FollowUpInputBehavior` 迁移为 `SnapAILogic` 实体源码。
- `FollowUpHistoryStore` 迁移为 `SnapAILogic` 实体源码。
- `ResultViewModel` 新增 `import SnapAILogic`。
- 审计修复 gate 新增这两个文件的实体源码和 app target 去重检查。

## 验证

- `scripts/check-logic-symlinks.sh`
- `scripts/run-audit-remediation-check.sh`
- `scripts/run-logic-tests.sh`
- `swift build`

## 剩余风险

当前仍有 72 个 symlink。后续迁移会遇到更多跨文件依赖,尤其是 `ResultCommand`、设置、历史、路由与 provider 模型。需要继续按依赖簇迁移,避免把仍被 symlink 文件依赖的类型单独移走造成自引用导入。
