# SnapAILogic 迁移计划

## 当前基线

- 版本:1.6.33
- `SnapAILogic` 真实 Swift 源码:18 个
- `SnapAILogic` 剩余 symlink:58 个
- 发布门禁:`scripts/check-logic-symlinks.sh` 要求 symlink 不得超过 58 个,真实源码不得少于 18 个
- 发布门禁同时禁止进入 `SnapAILogic` 的源码 `import SnapAILogic`,防止 symlink 文件形成 target 自导入

## 已迁移簇

- 结果面板命令:结果操作、固定、诊断、恢复建议、写回协调器
- 取词辅助:截图权限、截图临时文件、截图失败诊断、取词目标解析
- 输入与展示:流式输出累积、文本 diff、追问输入行为、追问历史
- 设置辅助:系统隐私设置 URL、设置窗口置顶状态
- 命令面板:搜索匹配与快捷键关键词扩展

## 后续迁移顺序

1. 写回/取词簇
   - 候选:`TextEditTransaction`, `WriteBackCommand`, `WriteBackCompatibility`, `TextCaptureDiagnostic`, `TextCapture`
   - 注意:这些文件共享 `PasteboardSnapshot`, `TextCaptureMethod`, `TextCaptureFailureReason`, `TextCaptureOutcome`;必须按簇迁移,避免 app target 与 library target 产生同名类型不一致。

2. 设置/自动化簇
   - 候选:`SettingsSection`, `AutomationRouter`, `AutomationURLCommand`, `SettingsToggleCommand`
   - 注意:`AutomationURLCommand` 牵涉动作、历史筛选、工作模式和设置枚举;迁移时需要一次性统一 public API。

3. 路由/模型簇
   - 候选:`ModelCapability`, `AIRequestRouter`, `RoutingDiagnostics`, `RoutingMetrics`, `FallbackRunner`
   - 注意:这些文件共享 `AIRequestRoute`, `AIRequestDiagnostics`, provider/model 类型;不应单文件迁移。

4. 历史/隐私簇
   - 候选:`History`, `HistoryStore`, `PrivacyHistoryTag`, `PrivacyFilter`, `PrivacySubmissionPreview`, `MarkdownExportSafety`
   - 注意:历史、导出和隐私 tag 互相引用,适合在完成 Settings/AppSettings 边界拆分后迁移。

5. 设置模型簇
   - 候选:`Settings`, `SettingsTypes`, `Provider`, `Action`, `AppSettingsImportSanitization`, `iCloudSync`
   - 注意:这是最大依赖簇,会影响几乎所有 app 工作流;应在前面小簇稳定后处理。

## 迁移规则

- 每次迁移后必须删除 app target 中重复源码。
- app target 只能通过 `import SnapAILogic` 使用已迁移 API。
- 不允许把已迁移真实源码退回 symlink。
- 不允许任何 `Sources/SnapAILogic` 源码导入 `SnapAILogic` 自身。
- 每轮迁移必须通过逻辑测试、SwiftPM build、macOS smoke 和 release preflight。
