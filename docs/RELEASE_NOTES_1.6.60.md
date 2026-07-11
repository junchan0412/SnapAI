# SnapAI 1.6.60

SnapAI 1.6.60 聚焦历史记录窗口的大列表性能、内存分配和搜索反馈。此前历史筛选是 SwiftUI view 的计算属性,一次 `body` evaluation 中多个消费者可能重复执行 SQLite FTS、内存 fallback、semantic search、facets 排序与上下文草稿构建。

## 性能

- 历史筛选、FTS、semantic search 和 facets 统一在 user-initiated 后台 queue 生成单一 presentation snapshot。
- view 渲染只读取已完成 snapshot,不再同步打开 SQLite 或执行全文扫描。
- 查询输入使用 180ms debounce,快速连续击键只触发稳定后的搜索。
- generation 校验禁止较慢的旧查询覆盖更新后的筛选结果。
- 历史窗口 view 与 model 拆分为独立文件,并加入行数增长门禁。

## 内存与状态更新

- `HistoryWindowView` 不再以 `@ObservedObject` 观察整个 `AppSettings`。
- model 只订阅 `history`、`historyLimit` 和 `savedHistoryFilters` 三个相关数据源。
- 标签草稿字典不再 `@Published`;编辑单条标签不会 invalidation 整个 LazyVStack。
- 历史卡片日期复用共享 `DateFormatter` 和 `ISO8601DateFormatter`,不再逐卡创建 formatter。
- presentation 只保存“可创建上下文包”标记,完整上下文正文在用户点击时按需生成。

## UI 与 UX

- 后台筛选期间显示“筛选中”状态,空结果区域显示明确的 loading feedback。
- 搜索提交可立即跳过剩余 debounce。
- 筛选结果未完成时暂时禁用复制、导出和创建上下文包,避免对旧 snapshot 执行操作。
- 本地验证中,13 条历史搜索 “Supabase” 后稳定显示 `1 / 13`,重置后恢复 `13 / 13`。

## 测试与门禁

- 新增 query debounce、即时 facet refresh 与 stale generation 拒绝测试。
- remediation gate 禁止恢复 broad `AppSettings` observation、`@Published tagDrafts`、view 内同步搜索和逐卡 formatter 分配。
- `SnapAILogic` 当前为 42 个真实源码、36 个 symlink。

## Release 资产

- `SnapAI-v1.6.60.zip`
- `snapai-manifest-v1.6.60.json`
- `snapai-manifest-v1.6.60.json.sig`
- `snapai-sbom-v1.6.60.json`
