# SnapAI 1.6.40 迭代报告

## 背景

`ModelSwitchCommand.swift` 没有其它 symlink 消费者,但原实现直接接收 `AIProvider`。直接迁移会让命令 factory 的公开 API 暴露 app target 的供应商模型类型。

## 本轮完成

- 新增 `ModelSwitchProviderInput`。
- `AppDelegate+CommandPalette` 负责将 `AIProvider` 映射为轻量输入。
- `ModelSwitchCommand.swift` 迁入 `Sources/SnapAILogic`,并从 app target 删除重复源码。
- 下调 `SnapAILogic` symlink 上限并提升真实源码下限。

## 当前边界状态

- `SnapAILogic` 实体 Swift 源码:23 个。
- `SnapAILogic` 剩余 symlink:53 个。
- 命令描述器小簇已完成 5 个文件,后续可继续处理模板、历史导出和上下文命令。
