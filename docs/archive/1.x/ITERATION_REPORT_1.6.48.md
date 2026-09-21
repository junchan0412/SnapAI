# SnapAI 1.6.48 迭代报告

## 背景

`ResultPersistence.swift` 原本同时承担纯结果指标、对话导出和 app target 历史写入。直接迁移会暴露 `AppSettings`, `AIAction`, `AIRequestDiagnostics` 等尚未迁移的大类型。`ConversationExport.swift` 只被 `ResultPersistence` 阻塞,适合在本轮一起迁移。

## 本轮完成

- 将 `ConversationExport` 迁入 `SnapAILogic`,保留 Markdown 导出、隐私保护正文省略和诊断脱敏行为。
- 将 `ResultPersistence` 迁入 `SnapAILogic`,保留完成耗时/字符数计算和纯文本诊断参数的对话导出工厂。
- 新增 `ResultPersistenceAppBridge`,在 app target 中保留 `AIRequestDiagnostics` 摘要转换和 `AppSettings.addHistory` 写入逻辑。
- `ResultViewModel` 继续使用原调用形态,由桥接层承担 app 类型适配。
- 下调 `SnapAILogic` symlink 上限并提升真实源码下限。

## 当前边界状态

- `SnapAILogic` 实体 Swift 源码:32 个。
- `SnapAILogic` 剩余 symlink:44 个。
- 结果持久化小簇完成;剩余 `ResultPersistence` 相关阻塞已清除,后续可继续评估 `RequestSession`, `FallbackRunner`, `HotKeyUtilities` 等 ready 候选。
