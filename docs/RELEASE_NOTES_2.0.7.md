# SnapAI 2.0.7

SnapAI 2.0.7 是自动化与「云 + 本地」补齐版本:七个功能面一次到位 —— 快捷指令入口、用量看板、历史语义搜索、截图本地 OCR、Apple 端侧模型、双模型对照、英文本地化;工程侧同时落了 AppDelegate 拆分、冷启动与内存基线、无障碍走查、发布链路进 CI。功能、配置、快捷键与历史记录完全兼容 2.0.x。

## 新功能

### 1. Shortcuts 集成(App Intents)

- 三个 `AppIntent`(`Sources/SnapAI/SnapAIIntents.swift`):**运行动作**(文本留空即读剪贴板)、**打开快捷提问**(可预填文本)、**切换模型**(按供应商 + 模型名),外加 `AppShortcutsProvider` 提供快捷指令里的即时入口。
- Intent 只做参数装配,命令语义仍归属 `AutomationURLCommand` —— `testAutomationIntentsCoverCoreShortcutsPaths` 断言三个 Intent 的输入能无损映射回既有 URL 命令,不产生第二套语义。
- 全一手框架、零依赖。其余 URL 命令继续走 `snapai://` 深链。

### 2. 用量看板

- 「AI 模型」页新增**使用统计**卡(`Sources/SnapAILogic/UsageDashboard.swift`):按供应商聚合请求数、成功率、平均耗时、最近使用,按请求数降序,空数据显示占位而非 0 行表格。
- 纯值语义、可测试,输入 `RoutingMetricsTable`,不碰文件与网络。
- **不展示 token 列**:请求层不记录 token,只用 elapsed 派生估算会虚构精确数 —— 宁可少一列,不给假数。

### 3. 历史语义搜索

- `HistoryEmbeddingSearch` 用一手 `NaturalLanguage`(`NLEmbedding`)做余弦相似召回,补充既有 SQLite FTS 关键词搜索,零依赖。
- 阈值 0.25(NLEmbedding 距离域 0…2,实测同义句约 0.23、无关句约 0.27)、候选上限 200、条目截断 500 字符 —— **宁可漏召回,不让语义噪声淹没精确结果**。
- 「找上次那个聊涨薪的对话」这类关键词搜不到的查询,语义能搜到。

### 4. 截图 OCR

- 快捷提问的贴图/截屏先走 `Vision` 本地文字识别(`Sources/SnapAILogic/ImageTextRecognition.swift`):纯文本截图直接转成文字发送,**图片不出本机** —— 更快、更便宜、不泄露图像给云端,并复用既有脱敏链路。
- 设置项「图片本地 OCR」默认开启;低置信度识别不硬转(阈值测试覆盖),识别失败回退原图发送。
- 测试:`testImageTextRecognitionRejectsUnreliableInput`、`testImageOCREnabledRoundTripsThroughSettingsAndCloudPayload`。

### 5. Apple 端侧模型

- 「本机模型」供应商预设(macOS 26 `FoundationModels`):**免费、离线、不出本机**,与 Ollama / LM Studio 预设一起构成「云 + 本地」。
- 弱链接 + `#available(macOS 26, *)` 守卫:macOS 14–25 编译通过、运行时显示「需要 macOS 26 及以上」;设备不支持 / Apple Intelligence 未开启 / 模型未就绪各有可读原因。
- `ModelCapabilityRegistry`(`ModelCapability.swift`)给端侧模型固定画像(无视觉、短上下文、快速省钱),路由据此降级提示,不会把它当成长上下文或视觉模型用。

### 6. 双模型对照(A/B)

- 同一个问题并排看两个模型的输出:核心 `ModelCompare`(中立配对,不替用户下结论)+ `TextDiff` 差异展示,窗口 `ModelCompareWindow`,命令面板入口。
- 测试:`testModelComparePairsOutputsWithNeutralSummary`。

### 7. 英文本地化

- `Localizable.strings`(zh-Hans / en 各 30 条)+ `SnapAIL10n` 助手,先覆盖主路径:设置分区标题、快捷提问、结果、设置标题等 13 处调用。
- 增量推进,未覆盖的长尾文案仍为中文;`testSettingsSectionTitlesResolveThroughLocalization` 锁定分区标题。

## 工程与性能

- **AppDelegate 拆分**:833 → 203 行,按启动装配 / 菜单栏 / 全局热键 / 面板编排拆成四个 coordinator(只持 weak host,无双向强引用),门禁锁 300 行上限。
- **界面层开始有测试**:`bindingForProvider` 等 keypath 读写下沉到 Logic 的 `SettingsPageBinding`,17 条断言覆盖命中、回退、未知 id 不写且不触发 commit、写后激活项归一化(零依赖政策不引入 ViewInspector)。
- **发布链路进 CI**:`readonly-preflight` 手动工作流跑可移植的只读前缀;本轮补上「范围空白检查」(干净检出上 `git diff --check` 恒为空)与「版本一致性」检查,签名/打包/SBOM/tag/Release 仍只在本机。
- **冷启动基线**:中位 182 ms、首启 624 ms(dyld+init 403 ms),`scripts/measure-startup.sh` 可复测;热启动 170 ms 几乎全在装配,是后续优化对象。
- **内存基线补齐**:设置窗口分 section 实测 32–63 MB(6 个 detail 本就按选中项构建),通用页改 `LazyVStack` 后 63 → 46 MB;菜单栏空闲 5 分钟稳 48 MB;流式峰值 58 MB;更新窗口(下载态)27 MB。
- **无障碍走查**:`scripts/ax-audit.sh` 遍历 AX 树(VoiceOver 朗读的那棵树)报告无可读名称的控件,16 个 surface 从 39 处降到 **0**;`docs/ACCESSIBILITY_WALKTHROUGH.md` 记录整改表与仍需人工过的 4 条。
- **截图自动化**:`scripts/screenshots-all.sh` 逐 surface 起隔离预览、取窗口号、`screencapture -l` 直出,release notes 配图不再靠手工。

## 兼容性

- 最低系统版本保持 **macOS 14**;端侧模型需要 macOS 26+,未达标时该预设显示不可用原因,其余功能不受影响。
- 配置、快捷键、历史记录与 2.0.x 完全兼容;不改变更新包的下载、校验与安装安全链路,manifest 公钥与签名连续性校验不变。
- 提供 ZIP、签名 manifest、签名文件与 SBOM。应用仍采用自签名分发,尚无 Apple notarization;首次安装步骤见 README。

## 截图

- `docs/screenshots/snapai-model-light.png`(用量看板卡)、`docs/screenshots/snapai-general-light.png`(通用页),2000×1440,窗口直出,由 `scripts/screenshots-all.sh` 产出。

## 已知事项

- 用量看板暂无 token 估算(请求层不记录 token)。
- 语义搜索是 FTS 关键词的**补充**而非替代:阈值偏保守,高确信才召回。
- Shortcuts 只覆盖三个核心命令,其余 URL 命令继续走 `snapai://` 深链。
- 仍无 Apple notarization(需开发者账号),Gatekeeper 首次打开步骤与 2.0.6 相同。
