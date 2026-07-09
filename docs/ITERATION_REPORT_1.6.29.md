# SnapAI 1.6.29 迭代报告

## 背景

审计报告指出 `SnapAILogic` target 仍通过 symlink 镜像 app 源文件。本轮选择结果面板命令簇,因为它的 UI 消费者可以通过 public library API 调用,且不会携带仍在 app target 中重复定义的业务类型。

## 本轮完成

- 将结果操作状态、菜单快捷键、命令面板 descriptor、恢复建议和结果固定命令迁入 `SnapAILogic`。
- 删除 app target 中对应的四个重复源码文件。
- 为结果菜单扩展补充 `SnapAILogic` 依赖。
- 将审计修复脚本扩展到 15 个已迁移实体源码。

## 当前边界状态

- `SnapAILogic` 实体 Swift 源码:15 个。
- `SnapAILogic` 剩余 symlink:61 个。
- 下一步优先继续迁移不涉及 `AppSettings` / `AIProvider` duplicated type 的闭合命令模块。
