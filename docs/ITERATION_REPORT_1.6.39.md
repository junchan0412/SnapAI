# SnapAI 1.6.39 迭代报告

## 背景

`SettingsToggleCommand.swift` 没有其它 symlink 消费者,但原实现直接读写 `AppSettings`。直接迁移会让 app target 的 `AppSettings` 与 `SnapAILogic.AppSettings` 发生类型错配。

## 本轮完成

- 将设置开关命令拆成 logic 纯状态与 app 设置桥接两层。
- `SettingsToggleCommandState` 承载开关状态,供 logic target 测试和命令文案生成使用。
- `SettingsToggleCommandAppSettings.swift` 留在 app target,负责实际读取和修改 `AppSettings`。
- `SettingsToggleCommand.swift` 迁入 `Sources/SnapAILogic`,并从 app target 删除重复源码。
- 下调 `SnapAILogic` symlink 上限并提升真实源码下限。

## 当前边界状态

- `SnapAILogic` 实体 Swift 源码:22 个。
- `SnapAILogic` 剩余 symlink:54 个。
- 命令描述器小簇已完成 4 个文件,后续可继续处理模板、历史导出、上下文和模型切换命令。
