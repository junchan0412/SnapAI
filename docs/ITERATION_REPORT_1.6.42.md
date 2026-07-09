# SnapAI 1.6.42 迭代报告

## 背景

`HistoryExportCommand.swift` 没有其它 symlink 消费者,但原实现直接接收 `HistoryEntry` 并返回 `HistoryFilterCriteria`。直接迁移会让 logic target 的公开 API 暴露 app target 中仍在迁移中的历史模型。

## 本轮完成

- 新增 `HistoryExportCommandInput`,只携带命令描述器需要的动作名、模型名、标签和收藏状态。
- 新增 `HistoryExportCommandCriteria`,用可选 facet 表示导出命令筛选意图。
- `HistoryExportCommandFactory` 改为只依赖轻量输入,内部保留历史 facet 排序、稳定 slug、隐私 tag 优先保留和关键词清洗行为。
- `AppDelegate+CommandPalette` 通过 `HistoryExportCommandAppBridge` 将 app 历史模型映射为 logic 输入,并将 criteria 映射回 `HistoryFilterCriteria` 执行导出。
- `HistoryExportCommand.swift` 迁入 `Sources/SnapAILogic`,并从 app target 删除重复源码。
- 下调 `SnapAILogic` symlink 上限并提升真实源码下限。

## 当前边界状态

- `SnapAILogic` 实体 Swift 源码:25 个。
- `SnapAILogic` 剩余 symlink:51 个。
- 命令描述器小簇已完成 7 个文件,后续可继续处理模板和历史上下文命令。
