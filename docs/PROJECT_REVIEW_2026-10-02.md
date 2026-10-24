# SnapAI 项目综合评估报告

评估日期：2026-10-02（Asia/Shanghai）
评估版本：2.0.8，Git `89ea7d7c0f3a48830293c59b201c8f89ada486f5`
重点：现有功能的真实完成度、界面与动画效果、性能证据、后续产品方向。

## 1. 总体判断

**SnapAI 已经具备可持续打磨的产品主线：在当前应用取词，交给选定的 AI 动作处理，阅读结果，确认后写回，再通过历史继续工作。** 这条路径比单纯的聊天窗口更有辨识度。原生 SwiftUI/AppKit、轻量浮窗、快捷键和本地历史，也与“尽量少打断工作”的定位一致。

当前最需要解决的是三个问题：

1. **功能宣传与实装成熟度存在差距。** 双模型对照尚未双跑，Shortcuts 仅返回提交确认，英文本地化局部完成。功能数量已经不少，应先让每个入口兑现承诺。
2. **输入与输出的呈现策略会影响实际效果。** OCR 自动移除原图可能损失视觉信息；逐字动画可能在模型完成后继续阻塞追问，并把完整结果误标为“部分结果”。
3. **底层性能有证据，完整 UI 性能证据仍不足。** 存储、解析、调度机制表现良好，但还没有本轮长文帧耗时、GPU、能耗或 release 长期内存数据。历史基线还存在 debug/release 口径混用。

建议产品方向：围绕“取词与截图 → 可靠处理 → 可控写回”深化。近期投入优先级应是**可靠性与实际能力补齐 > 长文阅读与输入体验 > 场景化自动化 > 大型知识库或泛用 Agent 平台**。

## 2. 评估方法与可信范围

本报告结合源码审查、现有文档、当前代码构建、离线测试、微基准和隔离 UI 预览。没有修改业务代码，没有调用真实 AI 供应商，没有使用用户真实历史或 API Key，也没有对生产应用执行写回。

| 证据类型 | 本次覆盖 | 能说明什么 |
| --- | --- | --- |
| 源码审查 | 功能入口、请求路由、输出生命周期、窗口、存储、隐私、自动化、发布与测试脚本 | 实现是否存在、调用是否接通、确定的状态与数据边界 |
| 离线逻辑测试 | 256 个手写 case；XCTest 包装为 1 个聚合 test | 已有断言覆盖下的逻辑正确性 |
| 流式 runtime | 5 组测试，含本地网络 fixture、取消与重启、输出调度、Markdown 合并 | 调度机制与模拟流行为，不代表所有供应商兼容性 |
| 优化微基准 | Markdown、think 标签处理、500 条 SQLite 历史 | 局部算法与存储耗时，不包含完整 SwiftUI 布局 |
| 当前源码 UI 预览 | 浅色结果页、原文展开、深色紧凑提问页、命令面板键盘执行、输入后 Return 提交 | 演示数据下的页面和交互；提交通往演示结果，不是真实推理 |
| 内存单点采样 | 当前 debug 预览，命令面板进入结果页并展开原文后采样 | 特定场景快照，不是 release 基线或泄漏结论 |

本次设备：Apple M4、16 GB，Mac16,10；macOS 27.2（26B5091g）；Xcode 27.0（27A266a）；Swift 6.4。最低运行系统声明为 macOS 14，Liquid Glass 和 Apple 端侧模型有更高系统要求；本轮没有在 macOS 14/15 上验证回退效果。

**AI 回答的准确性、翻译质量、实际 TTFT、跨应用取词/写回成功率，以及长时间使用稳定性，尚需专项实测。** 不将“代码接通”“演示可操作”或“测试通过”等同于这些指标已经达标。

## 3. 项目结构与工程状态

当前 Swift 源码共 170 个文件，约 29,936 行：App 层 79 个/13,447 行，`SnapAILogic` 90 个/16,369 行，updater 1 个/120 行。测试目录 17 个 Swift 文件，约 13,695 行。行数包含空行和注释，只用于规模说明。

主要结构：

- **App 层**：SwiftUI 页面、AppKit 窗口与系统集成，采用多个 coordinator 分担输入提交、路由尝试、输出与写回。
- **Logic 层**：动作与设置、请求协议、路由、隐私、历史、命令和生命周期逻辑。模块边界检查确认 90 个真实源文件、0 symlink、0 App/core 重复类型；它仍包含部分 macOS 框架代码，不应理解成完全跨平台的纯算法库。
- **存储与系统能力**：SQLite、UserDefaults、iCloud KVS、Vision、NaturalLanguage、FoundationModels、App Intents。
- **依赖与发布**：唯一外部 SwiftPM 依赖为固定版本 Sparkle 2.9.6。CI 定义了构建、逻辑与 runtime、供应链检查、模块边界检查和 benchmark smoke。

架构方向合理：将高频流式状态与大页面分离，将可测试的命令和生命周期逻辑从 UI 抽出，能减少维护风险。后续新增功能宜复用现有请求与命令机制，避免为每个入口另建一套状态机。

工程上仍有三个值得处理的点：聚合 XCTest 不利于单项定位和计时；standalone 备用测试入口实际编译失败；CI benchmark 仅检查能够运行，没有耗时阈值。最后一点是合理的 CI 噪声取舍，但需要固定设备上的独立性能回归记录来补足。

## 4. 现有功能全景

| 领域 | 已实现能力 | 实际成熟度与限制 |
| --- | --- | --- |
| 跨应用取词 | AX 优先、复制兜底、剪贴板保护、原应用记录、过期捕获结果隔离 | 主链路完整；真实兼容性仍取决于目标应用的 AX 和复制行为 |
| 动作与模板 | 提问、翻译、润色、总结、解释代码；自定义 Prompt、快捷键、分组、模型覆盖、推理与历史选项；模板导入导出 | 可配置程度高；模板是 Prompt，不代表具备邮件发送、会议录音或仓库分析集成 |
| 快捷提问 | 文本输入、单张图片、粘贴图片、整屏截图、本地 OCR、图片优化 | 已接通；没有区域截图、多图组合；OCR 自动转文本策略需调整 |
| 供应商与模型 | OpenAI 兼容、Anthropic、本地服务、Apple 端侧；切换、路由、fallback、工作模式 | 主干完整；模型能力主要靠名称推断，别名和新模型可能错分 |
| 结果工作区 | 原文编辑重发、动作/语言切换、流式输出、思考区、追问、重试、复制、导出、取消后保存部分结果 | 适合单次任务与短追问；没有完整的会话分支和并行任务管理 |
| 写回 | 差异确认、替换、追加、失败反馈、最近写回撤销 | 产品价值高；源文档变动、焦点和选区漂移仍需跨应用回归验证 |
| 历史记录 | SQLite、搜索、收藏、标签、过滤、保存筛选、导出、历史生成上下文包 | 默认 50 条，上限 500；原文 20,000 字符、结果 40,000 字符截断，属于轻量历史 |
| 语义搜索 | FTS/关键词与概念匹配、系统 NLEmbedding 补充召回 | embedding 仅处理前 200 条、每条前 500 字符；固定阈值，系统模型不可用时无此召回 |
| 上下文包 | 手工维护、历史创建、全局激活后加入 system prompt | 同时一个激活包；历史建包默认 12 条、每字段 1,500 字符；没有文件 RAG 和引用 |
| 命令与自动化 | 命令面板、URL Scheme、三个 App Intents、元数据打包 | Shortcuts 动作返回“已提交”文案，尚不返回 AI 正文供下一步处理 |
| 双模型对照 | 双栏展示、比较逻辑与入口 | **尚未接双跑**：左右都传入当前同一份结果，仅标签不同 |
| 用量看板 | 按供应商展示路由尝试数、成功率、平均耗时；底层另保留最近活跃时间 | 是请求统计；没有实际 token、费用、预算与日/月趋势 |
| Apple 端侧 | FoundationModels 可用性检查与本地请求 | 需 macOS 26+ 且 Apple Intelligence 可用；当前非流式、不支持图片 |
| 隐私与诊断 | 提交预览、规则脱敏、高风险确认、本地优先、历史控制、权限健康与诊断 | 机制较完整；预览/脱敏并非默认全开，应明确每次真实发送内容 |
| 同步 | iCloud KVS 配置同步与冲突处理逻辑 | 不同步历史、Key 和统计，容量 1 MB；仓库构建链路未见 iCloud KVS entitlement，需先核验发布能力配置，再做双设备验证 |
| 本地化与更新 | 主路径部分英文资源；Sparkle 手动检查更新、appcast 与签名链路 | 英文未全覆盖；自动检查默认关闭，真实升级安装及 Shortcuts 发现仍需人工验证 |

## 5. 最影响使用效果的具体问题

### 5.1 双模型对照尚未完成，优先校正产品承诺

`openModelCompare()` 的左右输入均为 `resultVM.completeText`，源码也明确注释为占位。用户看到两个模型标签，容易理解为两个模型独立生成了相同答案，当前实现不能支持这一判断。

短期应隐藏入口或标注演示；正式实现需要两份独立 request session、单侧取消与失败隔离、真实模型来源和独立耗时。完成后再增加“选用这一版”进入复制、历史或写回。

证据：[PanelCoordinator.swift:43](/Users/qidewei/Documents/SnapAI/Sources/SnapAI/PanelCoordinator.swift:43)。

### 5.2 OCR 自动移除图片，会改变用户问题的含义

OCR 默认开启；识别结果满足至少 8 字、平均置信度至少 0.5，就将文字加入输入框并移除原图。代码没有识别“纯文字截图”与“包含文字的图表/界面截图”的区别，因此布局、颜色、连线和图形可能丢失。

另外，发送只阻止正在截图的状态，没有等待 OCR 完成。相同图片在识别前后点击发送，可能分别走图片或纯文本通道。不能把本地 OCR 的存在概括成“图片始终不会离开本机”。

建议保留原图，提供“原图 / OCR 文字 / 图文一起”选择，显示识别状态与本次将提交的内容；不要让后台任务静默替换用户输入。区域截图和裁剪应紧接着做，可同时改善回答相关性、隐私与上传成本。

证据：[QuickInput.swift:29](/Users/qidewei/Documents/SnapAI/Sources/SnapAI/QuickInput.swift:29)、[QuickInput.swift:109](/Users/qidewei/Documents/SnapAI/Sources/SnapAI/QuickInput.swift:109)、[ImageTextRecognition.swift:17](/Users/qidewei/Documents/SnapAI/Sources/SnapAILogic/ImageTextRecognition.swift:17)。

### 5.3 部分再次处理路径不保留图片

修改原文重发、切换语言、切换动作等路径调用没有图片参数的 `sendInitial()`。图片问题在继续处理时可能退化为纯文本问题，应把附件纳入会话输入状态，只有用户主动删除时才移除。

证据：[ResultViewModel.swift:132](/Users/qidewei/Documents/SnapAI/Sources/SnapAI/ResultViewModel.swift:132)。

### 5.4 自动路由的可靠性受模型名称启发式限制

当前通过 `mini`、`flash`、`chat` 等名称推断速度或成本，通过部分模型名推断视觉能力；未匹配模型的上下文默认值为 8K。对于自定义别名和新模型，可能出现错误路由或不准确的长度提示。

建议让用户覆盖视觉、上下文窗口、推理支持、价格等元数据，并保留推断来源。现有路由指标可继续提供观测依据，不宜将名称分类当作性能或价格事实。

证据：[ModelCapability.swift:16](/Users/qidewei/Documents/SnapAI/Sources/SnapAILogic/ModelCapability.swift:16)。

### 5.5 自动化、语义搜索与用量看板都有明确上限

这些入口已经存在，下一步是深化能力：Shortcuts 返回正文和错误信息；历史检索缓存与扩大可检索内容；用量记录真实 token、价格和首字延迟。不要把这些深化建议列成“从零新增已存在的功能”。

证据：[SnapAIIntents.swift:29](/Users/qidewei/Documents/SnapAI/Sources/SnapAI/SnapAIIntents.swift:29)、[HistoryEmbeddingSearch.swift:13](/Users/qidewei/Documents/SnapAI/Sources/SnapAILogic/HistoryEmbeddingSearch.swift:13)、[UsageDashboard.swift:9](/Users/qidewei/Documents/SnapAI/Sources/SnapAILogic/UsageDashboard.swift:9)。

## 6. 界面与动画实现效果

### 6.1 视觉方向适合当前产品

当前预览中，结果页以正文为中心，原文默认折叠，复制和替换位于底部，追问紧随其后；深色紧凑提问页保留清晰的输入区、附件操作和发送按钮。在检查到的页面与尺寸中，没有发现主要操作被遮挡。命令面板支持方向键与 Return 执行；输入内容后发送按钮从禁用变为可用，Return 能进入演示结果。

材质主要用于原文区域、输入框和设置卡片，语义颜色与系统图标保持一致。界面依靠短暂反馈和静态层级引导注意力，没有持续装饰动画干扰正文。更值得投入的是长文排版、附件状态和结果控制，而非增加大面积背景动效。

限制：本轮预览没有覆盖所有设置页、不同桌面背景、系统增强对比度、Reduce Transparency 或完整 VoiceOver 读序；已有仓库截图用于了解历史设计，不能替代当前版本全页面验收。

### 6.2 动画清单

| 场景 | 当前实现 | 效果与性能判断 |
| --- | --- | --- |
| 浮窗出现/消失 | 160 ms opacity；进入 easeOut、退出 easeIn | 时长短、方向一致；Reduce Motion 时直接切换；防止旧退出回调关闭新窗口 |
| 按钮反馈 | hover 120 ms、按压 100 ms，前景/背景反馈和焦点描边 | 能表达状态；不是弹簧或缩放动画，支持 Reduce Motion |
| 命令面板定位 | 选中项 80 ms easeOut 滚动到可见位置 | 为键盘定位服务，支持 Reduce Motion |
| 生成状态 | 2 pt 系统不确定进度条；Reduce Motion 时静态色条 | 表达“正在处理”，不是已完成百分比 |
| 打字机 | 关闭/慢/标准/快；按 chunk 消费，静态尾部光标 | 有连续生成感，但会延后可操作时间；系统 Reduce Motion 未接入 |
| 自动跟随 | 最多 20 次/秒；流式滚动不加动画，用户滚动后暂停 | 避免叠加滚动动画与抢夺阅读位置 |
| 操作提示 | 代码块反馈 150 ms；结果 Toast 160 ms 淡入加位移；部分设置提示 180 ms | 反馈及时；Toast 和少量提示未统一遵守 Reduce Motion |
| Liquid Glass | macOS 26+ 原生玻璃 card/field/pill 与软滚动边缘；旧版本回退 | 主要是材质效果；未形成实质的控件液态融合/形变动画 |

项目未见 `glassEffectID`、`glassEffectUnion`、`glassEffectTransition`、`matchedGeometryEffect` 或实际 `interactive: true` 调用。结果 footer 虽有 `GlassEffectContainer`，内部按钮未直接使用 glassEffect。因此更准确的描述是“采用 Liquid Glass 材质”，不宜宣称复杂液态动画已实现。结果状态声明 `.transition(.opacity)` 也不代表在缺少 animated transaction 的路径中一定播放渐变。

证据：[FloatingPanel.swift:15](/Users/qidewei/Documents/SnapAI/Sources/SnapAI/FloatingPanel.swift:15)、[SnapAIUI.swift:130](/Users/qidewei/Documents/SnapAI/Sources/SnapAI/SnapAIUI.swift:130)、[SnapAILiquidGlass.swift:24](/Users/qidewei/Documents/SnapAI/Sources/SnapAI/SnapAILiquidGlass.swift:24)、[CommandPalette.swift:345](/Users/qidewei/Documents/SnapAI/Sources/SnapAI/CommandPalette.swift:345)。

### 6.3 打字机是当前最值得修正的动画行为

| 档位 | 每 tick 字符数 | interval | 理论 tick/s | 理论展示字符/s |
| --- | ---: | ---: | ---: | ---: |
| 慢 | 2 | 36 ms | 27.8 | 55.6 |
| 标准 | 4 | 18 ms | 55.6 | 222.2 |
| 快 | 8 | 12 ms | 83.3 | 666.7 |

以上由源码参数推算，**不是实测 FPS 或网络 token/s**。标准档如果网络结束时还积压 10,000 个待展示字符，理论仍需约 45 秒才能展示完成；实际调度延迟可能更长。这是条件举例，不表示正常请求都会积压这么多内容。

当前 `isStreaming` 要等动画队列排空才清零，随后才增加动作使用计数、保存正常历史并触发自动写回，追问也一直禁用。网络成功本身已先记录到路由诊断和成功率统计，两套完成口径并不相同。

**确定的语义问题**：网络已经成功结束、打字机仍在播放时，停止操作会立即展示完整回答，却将其标为“部分结果”；历史保存开启且写入成功时也带此标签。路由成功统计已记录，但动作使用计数不增加、自动写回不触发。用户只是想跳过动画，却进入了“取消生成”流程。

建议拆开 `generationCompleted` 与 `presentationCompleted`，增加“立即显示全文”，积压时自适应加速；Reduce Motion 时跳过逐字效果。展示状态不应改变已完成请求的真实性，也不应让“跳过动画”意外触发用户尚未确认的写回。

证据：[SettingsTypes.swift:19](/Users/qidewei/Documents/SnapAI/Sources/SnapAILogic/SettingsTypes.swift:19)、[ResultViewModel.swift:247](/Users/qidewei/Documents/SnapAI/Sources/SnapAI/ResultViewModel.swift:247)、[ResultViewModel.swift:412](/Users/qidewei/Documents/SnapAI/Sources/SnapAI/ResultViewModel.swift:412)、[ResultViewModel.swift:489](/Users/qidewei/Documents/SnapAI/Sources/SnapAI/ResultViewModel.swift:489)。

### 6.4 Markdown 能力比动画数量更影响阅读体验

流式期间显示纯文本，完成后转换为 Markdown。这降低了反复解析成本，但生成中会看到原始标记，完成时页面高度会改变。当前支持标题、段落、单层列表、引用、围栏代码及行内格式；没有独立的表格、数学公式、图片和嵌套 block 类型，有序列表也会丢失原始起始编号。

建议优先补表格、代码高亮与横向滚动、列表语义和阅读锚点。公式按实际用户需求随后增加。长文可以考虑“已完成段落稳定呈现、尾段保留流式文本”，但应先测量收益，避免引入更复杂且易错的增量解析。

证据：[MarkdownPresentation.swift:3](/Users/qidewei/Documents/SnapAI/Sources/SnapAILogic/MarkdownPresentation.swift:3)、[MarkdownView.swift:34](/Users/qidewei/Documents/SnapAI/Sources/SnapAI/MarkdownView.swift:34)。

## 7. 性能实测与已有优化

### 7.1 本次微基准

| 场景 | 样本与口径 | 当前代码中位耗时 | 2.0.0 文档参考 |
| --- | --- | ---: | ---: |
| 400 段纯文 Markdown | 15 次，优化构建 | 1.194 ms | 1.129 ms |
| 200 节混合 Markdown | 15 次，优化构建 | 3.518 ms | 4.592 ms |
| 6,000 组 think spans | 单 chunk，7 次 | 4.771 ms | 5.145 ms |
| 500 条历史批量写入 | 原文与结果各 2 KB，5 轮 | 14.353 ms | 36.849 ms |
| 30 次完整读取 500 条 | 5 轮；数字是 30 次总耗时 | 21.242 ms | 131.495 ms |
| 50 次收藏更新 | 5 轮；数字是 50 次总耗时 | 3.873 ms | 6.013 ms |

历史列来自 2.0.0 重构报告。本轮未与旧提交交替运行，不将差异归因于某次改动，也不据此宣称固定百分比提升。写入第一轮为 32.486 ms，其余四轮约 13.851–14.476 ms；首轮明显较慢，可能包含缓存与系统负载影响。存储脚本输出虽写“alternating runs”，本次没有传 baseline，实际是当前版本独立五轮。

### 7.2 已得到验证的机制

- **流式正文与思考状态独立观察**，同一轮主队列合并输出，避免所有 UI 每 token 更新。
- **打字机使用 chunk 队列和 String.Index**，空队列时停表，只有需要展示时启动 timer；runtime 验证空闲为 0 个活跃 timer。
- **Markdown 在后台构建，保留当前任务和最新待处理输入**；本次 runtime 再现 502 次 refresh 合并为 2 次 build、1 次 publication。
- **自动滚动节流且尊重用户阅读**，不会为每次增量叠加 ease 动画。
- **SQLite 复用连接、WAL、索引和事务**，收藏走局部更新；历史查询放后台并抑制过期结果。
- **部分文本设置采用 500 ms 延迟保存**；设置窗口关闭后释放 SwiftUI hosting controller，重开按需构建。

这些措施针对真实成本，值得保留。代码组织与微基准表明“已经做过有效性能优化”，但不足以证明“任何场景都不卡”。

证据：[ResultLiveOutputState.swift:36](/Users/qidewei/Documents/SnapAI/Sources/SnapAILogic/ResultLiveOutputState.swift:36)、[ResultStreamingCoordinator.swift:43](/Users/qidewei/Documents/SnapAI/Sources/SnapAI/ResultStreamingCoordinator.swift:43)、[MarkdownPresentationModel.swift:25](/Users/qidewei/Documents/SnapAI/Sources/SnapAI/MarkdownPresentationModel.swift:25)、[WindowCoordinator.swift:119](/Users/qidewei/Documents/SnapAI/Sources/SnapAI/WindowCoordinator.swift:119)。

### 7.3 启动与内存：明确区分当前采样和历史记录

| 数据 | 数值 | 可用范围 |
| --- | --- | --- |
| 本次 debug 预览，结果页展开原文 | physical footprint 41 MB，peak 42 MB，RSS 139,632 KB，采样时 CPU 0.0% | 进程运行约 68 秒的单点；先经过命令面板，不能代表 release 独立结果页或长期空闲 |
| 历史 2.0.7 exec→ready | 中位 182 ms，最小 172 ms，首次最大 624 ms | 文档中的同机 7 次测量，本轮未重测；中位不可当作真正冷启动 |
| 历史 2.0.7 隔离常驻 | 5 分钟 footprint 48 MB，peak 55 MB | 历史 release smoke 场景，本轮未重测 |
| 历史设置/流式预览内存 | 设置约 32–47 MB，流式 peak 58 MB 等 | 记录存在 debug/release 口径问题，应规范后重测再对外引用 |

RSS、physical footprint、peak 是不同指标，不应互相替代；CPU 0.0% 也是采样值，不等于始终无 CPU 消耗。本轮测试命令的最大 RSS 包含 Swift 编译器，不能作为 App 内存数据。

文档问题：`run-ui-preview.sh` 执行默认 `swift build`，却被内存报告引用为 release 预览。流式 fixture 文档还写“每片重渲染 Markdown”，而实际已是流式纯文本；演示规模与时长描述也有漂移。建议每份基线固定记录 commit、设备、配置、fixture 和实际命令。

证据：[run-ui-preview.sh:12](/Users/qidewei/Documents/SnapAI/scripts/run-ui-preview.sh:12)、[STARTUP_BASELINE.md](/Users/qidewei/Documents/SnapAI/docs/STARTUP_BASELINE.md)、[RUNTIME_MEMORY_BASELINE.md](/Users/qidewei/Documents/SnapAI/docs/RUNTIME_MEMORY_BASELINE.md)。

### 7.4 尚待实测的性能风险

| 风险 | 已知实现 | 下一步验证 |
| --- | --- | --- |
| 长文布局与完成瞬间重排 | 流式单个不断增长的 Text；完成后普通 VStack 构建所有 Markdown block | 10k/40k/100k 字符；记录主线程、完成切换、滚动和阅读位置 |
| 主线程同步落库的长尾 | 完成与收藏路径同步 upsert；SQLite 锁等待上限设置为 1 秒 | 锁竞争/慢盘场景下记录主线程等待，再决定异步持久化范围 |
| 语义查询重复计算 | 每次非空查询对有限历史做 embedding 补充；没有持久向量缓存 | 200/500 条、冷暖查询、连续输入 P50/P95，评估缓存收益 |
| 最快打字机多余更新 | 12 ms timer，理论 83.3 次/秒；未按显示刷新率协调 | 比较 60/120 Hz、关闭与开启动画的 CPU、帧耗时 |
| 电池/遮挡下成本 | 未见低功耗、thermalState 或 occlusionState 调度 | 被遮挡、切换应用、低功耗场景；隐藏会取消，不应误称关闭后 timer 泄漏 |
| 玻璃材质合成成本 | 多个材质区域，自定义 NSVisualEffectView 固定 active | Instruments/Core Animation 与 Energy Log；验证 Reduce Transparency |
| 图片与历史扩容 | 当前无完整图片峰值/大历史 UI 基线 | 大图添加/移除与 OCR、500 条滚动；数千条属于未来扩容压力测试 |

慢推理还有一个已验证限制：runtime fixture 设 timeout 5 秒、chunk 间隔 7 秒时，在收到 head 后超时。runner 接受并记录这一行为，不能因为 runtime 通过就认为长空闲流一定不会断开。后续可区分连接、首 token 和流式空闲超时。

## 8. 可靠性、隐私、可访问性和发布

现有优势包括提交前预览、脱敏、云端 fallback 确认、历史策略、剪贴板保护、写回确认和明确的诊断入口。它们直接支撑跨应用助手的可信度。

需要准确表达的边界：

- API Key 采用 AES.GCM 本地加密，但 master key 与密文同在当前用户目录；这避免明文配置泄露，不等于 Keychain 对同一用户进程的系统级隔离。该边界源码已有说明。
- 本地 OCR 仅说明识别在哪里发生，不能替代对真实网络 payload 的说明。
- 现有 AX 名称走查记录为 16 个 surface、0 无名称控件；这不是完整 VoiceOver、焦点顺序、对比度和 Reduce Motion 认证，本轮也未重新跑完整走查。
- 首次安装仍受自签名与未公证分发的摩擦影响；Sparkle 能规范更新，不会自动消除首次分发的所有问题。
- README 后部仍描述旧的 manifest/helper 更新链路，与 2.0.8 Sparkle 实现不一致，应合并清理。
- 英文仅局部 UI 接入资源，尚不能视为完整双语产品。

证据：[LocalSecretStore.swift:5](/Users/qidewei/Documents/SnapAI/Sources/SnapAILogic/LocalSecretStore.swift:5)、[ACCESSIBILITY_WALKTHROUGH.md](/Users/qidewei/Documents/SnapAI/docs/ACCESSIBILITY_WALKTHROUGH.md)、[UpdateCheckerApp.swift:3](/Users/qidewei/Documents/SnapAI/Sources/SnapAI/UpdateCheckerApp.swift:3)、[README.md:195](/Users/qidewei/Documents/SnapAI/README.md:195)。

## 9. 后续功能路线建议

以下成本是相对工程量判断，不是排期承诺。P0 表示下一轮先处理的信任与正确性问题，P1 为紧随其后的能力建设，P2 为验证需求后推进。

| 优先级 | 建议 | 用户价值 | 相对成本/依赖 | 验收标准 |
| --- | --- | --- | --- | --- |
| P0 | 对照入口与文档真实性校正 | 用户知道每项功能真正做了什么 | 低；界面与文档 | 未双跑时不冒充两个模型输出；更新和本地化说明一致 |
| P0 | 保留附件、OCR 三种提交模式 | 保住图表/界面信息，发送结果可预测 | 中；复用 Vision 与附件模型 | OCR 不静默删除原图；重试/换动作保持附件；明确本次 payload |
| P0 | 生成与展示状态分离、立即展示全文 | 减少等待，消除完整结果误标 | 中；生命周期与 UI | 网络完成后跳过动画不标 partial；统计口径清晰；不改变写回确认规则 |
| P0 | Reduce Motion 补齐和基线口径修正 | 一致的可访问体验与可信性能说明 | 低至中 | 所有自定义动效响应系统偏好；基线记录构建配置与 commit |
| P1 | 区域/窗口截图与发送前裁剪 | 减少噪声、隐私暴露和图片成本 | 中；现有截图流程 | 只处理所选区域，预览与实际输入一致 |
| P1 | Markdown 表格、代码与阅读锚点 | 提高日常回答的可读性 | 中；现有 renderer | 表格可读，长代码可滚动；完成重排不明显丢失阅读位置 |
| P1 | 模型能力元数据手工覆盖 | 让路由支持任意供应商和别名 | 低至中；模型设置 | 视觉、上下文、推理和价格来源可查、可改 |
| P1 | 真正双模型对照与选优 | 比较输出质量和模型性价比 | 中；独立 session | 两次真实请求、独立耗时和错误；单侧失败不影响另一侧 |
| P1 | Shortcuts 返回正文与结构化错误 | 从唤起入口升级为可组合自动化 | 中；请求完成等待机制 | 下一步快捷指令能直接使用 AI 正文；超时/取消可处理 |
| P1 | TTFT/token/费用与预算看板 | 解释慢在哪里、钱花在哪里 | 中；usage 解析和价格配置 | 实际值与估算分开；API 时间不混入动画时间 |
| P2 | 应用/项目专属配置 | 邮件、IDE、文档自动推荐动作/模型/上下文 | 中；已有来源应用信息 | 规则可见、可覆盖；不会静默提交内容 |
| P2 | 分段接受改写与源文校验 | 适合重要文稿，减少错误覆盖 | 中至高；diff 与 AX | 可逐段接受；源文本变化后提示重新确认 |
| P2 | 持久会话、分支和上下文压缩 | 延续任务，避免重复解释 | 中至高；数据库与 token 预算 | 恢复原图与轮次；分支保留原版本；压缩可见 |
| P2 | 项目文件检索与引用 | 将上下文包升级为可核对资料助手 | 高；文件分块、索引、权限和引用 | 回答引用文件/页码；删除资料后不再检索到 |

建议按三个阶段推进：

1. **可信维护版**：完成 P0、修好 standalone runner，补关键回归 fixture。先把现有行为说清楚、做正确。
2. **截图与阅读增强版**：区域截图、附件模式、表格/代码、模型能力覆盖，加上长文性能测量。直接改善每天最常用的路径。
3. **场景效率版**：从真正双模型、可组合 Shortcuts、应用专属配置中选择最符合实际用户需求的两项；有明确资料需求后再做文件检索。

不建议近期优先投入持续背景动效、复杂主题系统或宽泛 Agent 平台。它们增加维护面，与当前主要问题的改善关系较弱。

## 10. 下一轮如何验收效果和性能

### 功能效果

建立小而固定的任务集：中英翻译、润色、长文总结、代码解释、图表/界面/纯文字截图。逐项记录是否保留信息、格式是否符合要求、是否一次完成、是否需要重试和人工修改。AI 质量最好做盲评；先看任务完成率和修改量，再比较模型名称。

跨应用重点覆盖浏览器网页、TextEdit、一个 Electron 编辑器和一个办公应用；分别验证 AX 取词、复制兜底、焦点变化、源文被修改后的写回、剪贴板还原。报告最终应给成功率与失败条件，不能只写“支持任意应用”。

### 动画与性能

| 场景 | 应记录指标 | 建议验收方向（尚非达标事实） |
| --- | --- | --- |
| 打开输入/结果窗 | 用户触发→可输入/可读的 P50/P95，首次与重复分别记录 | 不只测 main→ready；显示内容不被长动画阻塞 |
| 流式请求 | 请求开始、首 token、网络结束、展示结束、Markdown ready | 五个时点独立；可跳过展示，完成含义一致 |
| 长回复与最终重排 | 10k/40k/100k 字符的帧耗时、主线程停顿、内存峰值 | 60 Hz 参考帧预算 16.7 ms，120 Hz 为 8.3 ms；统计超预算比例 |
| 历史查询 | 50/200/500 条的冷暖 P50/P95、连续输入与取消 | 无明显输入阻塞，旧查询不覆盖新结果 |
| 图片流程 | 大图解码/OCR/删除峰值，真实上传量，图片模式一致性 | 图表不丢视觉，删除后不持续累积资源 |
| 窗口生命周期 | 重复开关 30 次、后台/遮挡、5–30 分钟空闲 | 比较相同场景稳态与趋势，区分系统缓存与持续增长 |
| 可访问性 | Reduce Motion/Transparency、增强对比度、VoiceOver、键盘 | 显示与焦点可预测；不能仅以控件有名称代替完整检查 |

建立固定设备 release 基线后，再设回归阈值。当前不宜凭一次微基准或截图承诺稳定 60/120 FPS，也不宜在没有热点证据时展开大规模重构。

## 11. 本轮验证记录与复核入口

| 命令/检查 | 结果 |
| --- | --- |
| `scripts/run-logic-tests.sh` | 通过；1 个聚合 XCTest，内部 256 case，0 failures；测试执行 3.443 s，含增量构建约 16.74 s |
| `scripts/run-streaming-runtime-tests.sh` | 5 组通过；含优化编译约 34.11 s；慢流 timeout 行为按 NOTE 接受 |
| `scripts/benchmark-streaming.sh` | 通过；数值见第 7 节 |
| `scripts/benchmark-storage.sh` | 通过；当前版本 5 轮，没有旧提交交替对照 |
| `scripts/check-logic-symlinks.sh` | 通过；90 logic 文件、0 symlink、0 重复类型 |
| `SNAPAI_MANUAL_TEST_RUNNER=1 scripts/run-logic-tests.sh` | **失败**；`SettingsPageBindingTests.swift:2` 无条件导入 `SnapAILogic`，standalone 路径未生成此模块；不是业务断言失败 |
| 当前源码隔离 debug 预览 | 已验证本文列明的页面和演示交互；临时 bundle 只为审查组装，不作为发布产物 |
| release 打包、真实更新、真实 Shortcuts 执行、完整 App runtime/AX 走查、GPU/FPS/能耗 | 本轮未执行 |

测试原始日志保存在本机临时目录，关键结果已写入本文，临时目录可能被系统清理：

- [逻辑测试日志](/tmp/snapai-audit-20261002/logic-tests-swiftpm.log)
- [流式 runtime 日志](/tmp/snapai-audit-20261002/streaming-runtime.log)
- [解析微基准日志](/tmp/snapai-audit-20261002/benchmark-streaming.log)
- [存储五轮原始数据](/tmp/snapai-audit-20261002/benchmark-storage.log)
- [debug 预览内存快照](/tmp/snapai-audit-20261002/runtime-preview.md)
- [standalone 失败日志](/tmp/snapai-audit-20261002/logic-tests.log)

本轮交付为评估报告。上述缺陷与建议尚未实施；业务代码保持原样。
