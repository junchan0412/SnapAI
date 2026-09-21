# SnapAI 1.6.37 迭代报告

## 背景

`DisplayBehaviorCommand.swift` 没有其它 symlink 消费者,但原 factory 直接暴露 `TypewriterSpeed`。如果直接迁移,app target 会把本地 `TypewriterSpeed` 传给 `SnapAILogic.TypewriterSpeed`,造成类型错配。

## 本轮完成

- 将显示行为命令 factory 输入改为 `TypewriterSpeedCommandInput`。
- `DisplayBehaviorCommandAction.setTypewriterSpeed` 改为传递 speed id。
- `AppDelegate+CommandPalette` 负责把 speed id 映射回 app target 的 `TypewriterSpeed`。
- `DisplayBehaviorCommand.swift` 迁入 `Sources/SnapAILogic`,并从 app target 删除重复源码。
- 下调 `SnapAILogic` symlink 上限并提升真实源码下限。

## 当前边界状态

- `SnapAILogic` 实体 Swift 源码:20 个。
- `SnapAILogic` 剩余 symlink:56 个。
- 命令描述器小簇已完成 2 个文件,后续可继续处理模板、历史导出、上下文和模型切换命令。
