# SnapAI 1.6.50 迭代报告

## 背景

`AutomationURLCommand.swift` 原本同时包含纯 URL 解析值对象和依赖 `AppSettings` / `AIAction` 的 app 选择逻辑。直接公开整个文件会把设置模型过度暴露;只迁移文件又会让 app target 与 logic target 中的同名设置/历史类型发生不匹配。

## 本轮完成

- 将 `AutomationURLCommand` 迁入 `SnapAILogic` 真实源码。
- 公开自动化 URL 解析所需的最小值对象:`AutomationRunOptions`, `AutomationHistoryContextOptions`, `AutomationURLCommand`。
- 将 `TargetLanguage`, `HistoryFilterCriteria`, `AIRoutingPreference`, `WorkModePreset`, `TypewriterSpeed` 的跨 target 必要成员公开,仅用于 URL command 关联值和桥接转换。
- 新增 `AutomationURLCommandAppBridge`,保留 app 专属的模型选择、上下文选择、动作匹配、设置 section 匹配、写回策略和 action override 应用。
- `AutomationCommandHandler` 对 logic URL command 中的 criteria / preference / mode / speed 做显式转换后再写入 app 设置。

## 当前边界状态

- `SnapAILogic` 实体 Swift 源码:34 个。
- `SnapAILogic` 剩余 symlink:42 个。
- 自动化 URL 解析主体迁移完成;后续可以继续评估 `FallbackRunner`, `RequestSession`, `HotKeyUtilities`, `WriteBackCommand` 等候选,但这些候选需要更明确的 DTO 或成簇迁移。
