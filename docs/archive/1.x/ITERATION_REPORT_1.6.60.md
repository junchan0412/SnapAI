# SnapAI 1.6.60 迭代报告

## 问题定位

历史窗口同时存在四类 SwiftUI 热点:

1. `filtered` 计算属性在 `body`、toolbar、summary、导出和上下文入口中被多次访问。
2. 带 query 时每次访问都会同步打开 SQLite、执行 FTS、内存 compact fallback 和 semantic search。
3. view 观察整个 `AppSettings`,模型、外观等无关设置也会触发历史列表刷新。
4. 每个标签字符都会发布完整 `tagDrafts` 字典;每张卡片还会创建自己的日期 formatter。

## Presentation snapshot

新的 `HistoryWindowModel` 保存唯一 `HistoryWindowPresentation`。每次有效输入变化只生成一次:

- 当前 criteria 对应的 entries。
- 动作、模型和标签 facets。
- 总记录数与上下文可用性标记。

计算在 user-initiated 后台 queue 完成,主线程只接收最终值。snapshot 同时保存其 criteria,确保复制、导出和上下文操作始终与展示结果一致。

## 输入合并与并发一致性

- query 变化等待 180ms,facet、收藏和历史数据变化立即刷新。
- 每次计划刷新递增 generation。
- 后台任务完成时只有最新 generation 可以发布。
- 新 query 提交时可立即刷新,窗口关闭时取消尚未触发的 debounce work item。

## 状态与内存收敛

- view 的 `settings` 改为普通引用,避免整个 `ObservableObject` fan-out。
- Combine 仅监听三个历史相关 publisher,并统一切回主队列更新 model。
- 标签草稿保持非 published mutable state,TextField 自身负责编辑显示,提交时才写入设置与 SQLite。
- 完整上下文包草稿不再常驻 presentation;点击按钮后才从当前 entries 生成。
- compact 与 ISO 日期格式器改为文件级共享缓存。

## 验证结果

- remediation gate、logic suite、SwiftPM build 与 macOS smoke 通过。
- logic target:41 → 42 个真实源码;symlink 保持 36 个。
- HistoryWindow view:481 → 423 行;后台 model 独立为 184 行。
- 本地真实历史窗口完成搜索、结果计数和筛选重置验证,未触发第三方 AI 请求或修改历史内容。

当前环境没有可用的 Instruments `xctrace`,因此本轮结论以明确的同步 I/O 移除、计算次数边界、回归测试和真实 UI 行为为证据,不虚构帧率或 CPU 百分比。
