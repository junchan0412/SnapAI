# SnapAI 1.6.43 迭代报告

## 背景

`HistoryContextCommand.swift` 与历史导出命令同属命令描述器小簇。原实现直接接收 `HistoryEntry` 并返回 `HistoryFilterCriteria`,迁移前需要把历史模型和筛选模型从 public API 中剥离。

## 本轮完成

- 新增 `HistoryContextCommandInput`,携带动作、模型、标签、收藏状态和“可作为上下文素材”的布尔状态。
- 新增 `HistoryContextCommandCriteria`,用轻量 facet 表达命令意图。
- `HistoryContextCommandFactory` 改为只依赖轻量输入,保留可用记录计数、稳定 slug、facet 排序和关键词清洗行为。
- `HistoryExportCommandAppBridge` 增加上下文命令桥接,由 app target 映射 `HistoryEntry` 与 `HistoryFilterCriteria`。
- `HistoryContextCommand.swift` 迁入 `Sources/SnapAILogic`,并从 app target 删除重复源码。
- 下调 `SnapAILogic` symlink 上限并提升真实源码下限。

## 当前边界状态

- `SnapAILogic` 实体 Swift 源码:26 个。
- `SnapAILogic` 剩余 symlink:50 个。
- 命令描述器小簇已完成 8 个文件,后续主要剩余 `ActionTemplateLibrary` 及更大的历史/设置/路由簇。
