# SnapAILogic 迁移计划

## 当前基线

- 版本:1.6.72
- `SnapAILogic` 真实 Swift 源码:47 个
- `SnapAILogic` 剩余 symlink:36 个
- 发布门禁:`scripts/check-logic-symlinks.sh` 要求 symlink 不得超过 36 个,真实源码不得少于 47 个
- 发布门禁同时禁止进入 `SnapAILogic` 的源码 `import SnapAILogic`,防止 symlink 文件形成 target 自导入
- 迁移候选分析:`scripts/report-logic-migration-candidates.sh` 会列出每个剩余 symlink 的 top-level type 消费者,并用 `boundary` 标记 `cluster` / `app-api` / `isolated`,用于决定下一轮是按簇迁移、加 app bridge/DTO,还是可直接迁移。

## 已迁移簇

- 写回命令:`WriteBackCommand` 使用 `WriteBackCommandInput` / `TextWriteBackOperation` DTO,app target 只保留 `TextWriteBackRecord` bridge。
- 写回状态:`TextWriteBackLogic` 统一撤销状态、目标快照、失败诊断、追加 payload 与粘贴时序;`TextEditTransaction` 保持为 app-only AppKit adapter。
- 写回兼容性:`WriteBackCompatibility` 已迁为真实 logic 源码,app target 不再保留重复定义。
- 自动更新:`UpdateChecker` 只保留版本、Release/manifest/signature/digest、安装日志和签名解析纯逻辑;`UpdateCheckerApp` 负责网络、AppKit UI、解压与安装。
- 菜单边界:`MenuCoordinator` 保持为 app-only AppKit adapter,模型切换菜单复用 `ModelSwitchCommandFactory` descriptor,不再进入 logic target。
- `TypewriterBuffer`:流式 UI 只消费增量 chunk,避免在 app target 中维护长文本索引与重复前缀复制。
- 结果内容展示:`ResultContentPresentation` 将等待、流式纯文本和完成态 Markdown 明确分层,并集中定义 30Hz 自动滚动策略,避免流式阶段反复解析完整 Markdown。
- 历史窗口刷新:`HistoryWindowRefreshPolicy` 集中定义搜索 debounce 与 generation 校验;app target 的 `HistoryWindowModel` 负责后台构建 presentation snapshot,SwiftUI view 不再直接执行数据库与 semantic search。
- 结果实时状态:`ResultLiveOutputState` 将 output 与 thinking 分为独立 observable source,重复文本更新短路;app target 仅保留具体 SwiftUI 内容、滚动观察器和操作工具栏。
- 结果完成状态:`ResultCompletionState` 将 elapsed 与 characterCount 合并为可去重 snapshot;`ResultDiagnosticTextSnapshot` 将 full/brief diagnostics 合并为单一根级 value update。
- 结果完成生命周期:`ResultCompletionLifecycle` 保证每个请求只完成一次并跟踪历史持久化;app target 的 `ResultCompletionCoordinator` 统一完成指标、usage、history、settings save 与 auto replace 副作用。
- 路由 attempt 协调:`ResultRouteAttemptCoordinator` 在 app target 统一 preflight skip、scoped settings、成功/失败 diagnostics 与 routing metrics;VM 仅保留 streaming UI 状态归约。
- 请求 preparation 协调:`ResultRequestPreparationCoordinator` 在 app target 统一 privacy payload counts、context/payload/pipeline diagnostics、candidate routes 与 no-candidate recovery;VM 仅解释 ready/unavailable。
- 流式呈现生命周期:`ResultStreamingLifecycle` 统一 visible/thinking accumulator、typewriter pending chunks 与 provider-finished 状态;app target 的 `ResultStreamingCoordinator` 只管理主线程 Timer 和 leaf-state 回调。
- 结果 submission 协调:`ResultSubmissionCoordinator` 在 app target 统一 source/follow-up privacy preparation、initial message 和 conversation append;VM 不再持有 history 或 pending image payload。
- 结果操作反馈:`ResultOperationFeedback` 以真实 logic 源码定义 success/warning 反馈与安全 export filename;app target coordinator 负责 pasteboard/save panel,结果页、历史窗口、历史设置与 code block 复用独立 leaf feedback 通道。
- Markdown presentation:`MarkdownPresentationBuilder` 以真实 logic 源码完成 block 与 inline attributed parsing;app target model 在后台构建并用 generation/source 双校验发布 snapshot。

- 结果面板命令:结果操作、固定、诊断、恢复建议、写回协调器
- 取词辅助:截图权限、截图临时文件、截图失败诊断、取词目标解析
- 取词诊断:取词状态摘要与恢复建议,app target 通过轻量枚举桥接取词实现状态
- 输入与展示:流式输出累积、文本 diff、追问输入行为、追问历史
- 结果持久化:完成指标和对话 Markdown 导出,app target 通过桥接保留历史写入
- 设置辅助:系统隐私设置 URL、设置窗口置顶状态
- 命令面板:搜索匹配与快捷键关键词扩展
- 命令 ID:slug 生成与 ID 去重工具
- 自动化入口:URL 命令解析与薄路由,app target 通过桥接保留设置/动作选择
- 设置导航:设置页 section 值对象和展示元数据
- 更新诊断命令:安装日志命令字幕与路径脱敏
- 动作命令:动作命令面板 descriptor 与轻量输入 DTO
- 显示行为命令:Dock、开机启动和打字机速度 descriptor 与轻量输入 DTO
- 工作模式命令:模式切换 descriptor 与轻量输入 DTO
- 设置开关命令:开关解析、标题和纯 state 变更,app target 通过扩展桥接 `AppSettings`
- 模型切换命令:模型切换 descriptor 与轻量 provider 输入 DTO
- 路由/上下文命令:路由偏好与上下文包 descriptor 输入 DTO
- 动作模板库:内置模板、导入导出和安装去重逻辑,app target 通过 `ActionTemplateAction` 桥接 `AIAction`
- 历史导出命令:历史导出 descriptor 与轻量历史输入/criteria DTO
- 历史上下文命令:上下文包创建 descriptor 与轻量历史输入/criteria DTO

## 迁移候选分析

运行:

```bash
scripts/report-logic-migration-candidates.sh
```

输出中的 `blocked` / `cluster` 表示该文件的公开类型仍被其它 symlink 文件消费,单独迁移会造成 app target 与 `SnapAILogic` target 同名类型不一致,或者迫使 symlink 文件 `import SnapAILogic`。这类文件必须按照下面的簇一次性迁移。

输出中的 `bridge` / `app-api` 表示没有 symlink 消费者,但 app 或测试仍直接消费其类型。迁移前应先改为 DTO 或 app bridge,避免公开 API 暴露仍在 app target 中重复存在的类型。

输出中的 `ready` / `isolated` 表示当前没有检测到 symlink 或 app/test 消费者,通常可以作为最小迁移候选。

## 后续迁移顺序

1. 写回/取词簇
   - 已完成:`WriteBackCommand`, `WriteBackCompatibility`, `TextWriteBackLogic`;`TextEditTransaction` 已收窄为 app-only adapter。
   - 候选:`TextCapture`
   - 注意:`TextCapture` 仍与 `PasteboardSnapshot`、AX/AppKit 捕获实现和应用激活强耦合;后续应继续抽取纯状态与诊断,而不是把 AppKit 实现整体迁入 logic target。

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

6. 命令描述器小簇
   - 已完成:`ActionCommand`, `DisplayBehaviorCommand`, `WorkModeCommand`, `SettingsToggleCommand`, `ModelSwitchCommand`, `RoutingContextCommand`, `ActionTemplateLibrary`, `HistoryExportCommand`, `HistoryContextCommand`
   - 后续候选:无;后续需进入更大的写回/取词、设置/自动化、路由/模型、历史/隐私簇。
   - 注意:即使分析脚本显示 `ready`,仍需先把 factory 输入改为 DTO,避免公开 API 暴露仍在 app target 重复存在的 `AIAction`, `AIProvider`, `HistoryEntry`, `ContextProfile` 等类型。

## 迁移规则

- 每次迁移后必须删除 app target 中重复源码。
- app target 只能通过 `import SnapAILogic` 使用已迁移 API。
- 不允许把已迁移真实源码退回 symlink。
- 不允许任何 `Sources/SnapAILogic` 源码导入 `SnapAILogic` 自身。
- 每轮迁移必须通过逻辑测试、SwiftPM build、macOS smoke 和 release preflight。
