# SnapAI 1.6.36 迭代报告

## 背景

1.6.35 新增的迁移候选分析显示 `ActionCommand.swift` 没有其它 symlink 消费者,但原 factory 直接接收 `AIAction`,如果直接迁移会暴露 app target 里的大设置模型类型。

## 本轮完成

- 将动作命令 factory 输入改为 `ActionCommandInput`。
- `AppDelegate+CommandPalette` 负责把 `AIAction` 映射为轻量输入。
- `ActionCommand.swift` 迁入 `Sources/SnapAILogic`,并从 app target 删除重复源码。
- 下调 `SnapAILogic` symlink 上限并提升真实源码下限。
- 更新 README、迁移计划和发布说明。

## 当前边界状态

- `SnapAILogic` 实体 Swift 源码:19 个。
- `SnapAILogic` 剩余 symlink:57 个。
- 后续适合继续处理命令描述器小簇,但每个 factory 都需要先确认公开 API 不泄露 app target 重复类型。
