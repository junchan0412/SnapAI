# 路线落实后的性能验收记录（2026-10-04）

本轮对应 `PROJECT_REVIEW_2026-10-02.md` 第 10 节。逻辑微基准、完整窗口体验和跨应用效果分别记录，测试通过不等于窗口帧率或真实模型质量达标。

## 测量方法

执行 `scripts/benchmark-roadmap.sh docs/performance/ROADMAP_2026-10-04.json`。脚本先复制实际编译源码到临时目录，以 `swiftc -O` 编译独立 runner，再串行测量；不复用 SwiftPM 构建目录、不访问用户历史库、不请求 AI 服务。JSON 保存 commit、工作区 dirty hash、编译源码 hash、二进制 hash、设备、macOS、Swift/Xcode、命令、全部原始样本和 P50/P95。

- Markdown：10k、40k、100k 个 Swift `Character`，包含中英正文、emoji、标题、嵌套/任务列表、表格、Swift 代码。测量 block/行内属性/高亮 token 构建；每档预热 1 次、测量 30 次。截断的最后一段按实际不完整 Markdown 处理。
- 历史：50、200、500 条合成记录；每条原文 2000 字符、结果 2000 字符加检索词，10% 包含 `needle`。分别测量全部读取、SQLite FTS 和窗口实际使用的 `HistorySearch.filteredEntries`（FTS、内存匹配、概念召回、可用的系统 NLEmbedding）。完整搜索中的内存记录已预加载。
- 冷连接：每个样本新建 `HistoryStore` 并打开已有数据库，包含连接准备/关闭成本；**不清空 OS 文件缓存，也不代表整机冷启动**。暖连接复用预热后的同一 SQLite 连接。系统 embedding 可用性写入 JSON；模型资源已探测，冷连接不代表 embedding 冷启动；当前完整搜索也已预热同一query的系统距离缓存。
- 每组 30 个样本，P50/P95 使用 nearest-rank：排序后取 `ceil(p × n) − 1`。合成数据先验证行数和必需命中，避免将失败后的空结果当成快速查询。

## 本轮实测

设备为 Apple M4 / 16 GB，macOS 27.2；当前工作区优化构建，每组30次。完整原始记录见 [当前基线 JSON](performance/ROADMAP_2026-10-04.json)。

| 场景 | 规模 | P50 | P95 |
| --- | --- | ---: | ---: |
| Markdown混合解析 | 10000字符 | 1.825 ms | 2.218 ms |
| Markdown混合解析 | 40000字符 | 7.284 ms | 7.475 ms |
| Markdown混合解析 | 100000字符 | 18.246 ms | 18.782 ms |
| 完整历史搜索（暖连接/暖距离缓存） | 50条 | 30.606 ms | 31.183 ms |
| 完整历史搜索（暖连接/暖距离缓存） | 200条 | 118.323 ms | 131.811 ms |
| 完整历史搜索（暖连接/暖距离缓存） | 500条 | 290.537 ms | 305.284 ms |

基线 commit：`89ea7d7c0f3a48830293c59b201c8f89ada486f5`（含未提交修改），实际编译源码 SHA-256：`90395da01125fbf51d7db80f9b23023dfbbf16f92c66f9c52439f2d0e3b21b98`。该hash记录脚本复制的真实源码，不将HEAD视为完整待发布版本。

历史查询的冷连接/暖连接全部样本（读取、FTS、完整搜索）保存在 JSON。上述完整搜索已预热**系统距离缓存**；合成记录具有相同的前500字符，只使用固定`needle`查询，缓存命中率很高。数据说明固定查询及重复文本的收益，不能代表不同查询、大量唯一文本、首次embedding查询或所有真实历史。

为查明热点，另用 `SNAPAI_BENCHMARK_SAMPLES=1 SNAPAI_BENCHMARK_EMBEDDING_REF=HEAD scripts/benchmark-roadmap.sh docs/performance/ROADMAP_BEFORE_CACHE_2026-10-04.json` 替换为修改前的语义检索实现，其余源码同一工作区；[原始探索性样本](performance/ROADMAP_BEFORE_CACHE_2026-10-04.json)显示暖连接完整搜索50条约4,465 ms，200条约17,973 ms，500条约18,137 ms。**旧实现每组仅1次，不将其作为P50/P95，也不据此宣称普遍提升百分比。** 原计划30次的旧实现运行约20分钟仍未完成，已中止，没有把未完成数据计入结果。

最终优化保留系统 `NLEmbedding.distance` 原始值，按query、实际截断文本、语言和embedding revision做512项有界内存缓存。首次不同query/text组合仍可能昂贵。2026-10-06新增cooperative cancellation：候选/语言边界检查取消，新输入取消旧查询，generation继续拒绝过期发布；词法/FTS结果先显示，再补语义结果。该增量已通过逻辑回归与App构建，单次系统distance调用仍不可抢占；本表是此前缓存版数据，不能当作新实现端到端时延。


## Markdown 功能验收范围

已实现表格列对齐与横向滚动、代码横向滚动和常用语言基础高亮、有序列表原始编号、嵌套层级、任务勾选状态及续行。未知代码语言保留原文显示，复制始终使用原始代码。

完成态使用按需block布局；重排会在用户停止跟随时保存正文内部相对位置，并在 Markdown ready 后恢复；用户继续滚动会取消恢复，跟随模式照常定位底部。这是相对位置保持，尚不是逐字/source-line 锚点。解析、代码保真和位置计算已有针对性逻辑测试；完整 App 中的实际滚动误差仍需人工验收。

## 100k 窗口布局与内存观察

实际使用 `SNAPAI_PREVIEW_CONFIGURATION=release scripts/run-ui-preview.sh result-long-100000 light` 构建隔离bundle；这是启用fixture宏的优化构建，不是正式发布产物。通过原生UI检查了表格表头、列对齐、基础代码高亮、原文折叠区及底部操作未被遮挡。

100k完成态原先一次性创建所有block，Core Animation占用很高。本轮将Markdown完成态改为LazyVStack按需布局，并把自动滚动目标放到独立末尾锚点。初次尝试出现仅滚到约68%的偏差，修复锚点后AX滚动值约0.9986，正文确为最后的填充段落，底部操作可用。

| 独立运行实例 | 进程已运行 | physical footprint | 进程peak | RSS | 原始记录 |
| --- | --- | ---: | ---: | ---: | --- |
| 改前VStack，100k末尾 | 04:20 | 369 MB | 439 MB | 456,944 KB | [改前快照](performance/UI_100K_2026-10-04_START.md) |
| 改后LazyVStack＋末尾锚点 | 15:38 | 65 MB | 144 MB | 145,216 KB | [改后快照](performance/UI_100K_2026-10-04_FINAL.md) |

改前Core Animation为269.4 MB；改后约9.4 MB。**两次运行时长不同，末次采样后电脑操作工具报告Mac已锁定，采样瞬间的遮挡状态未单独记录。这不是严格相同可见性/温度/运行时长的A/B实验，不换算普遍提升百分比，也不代表完整滚动后的峰值或泄漏结论。** 当前观察支持保留按需布局，解锁后仍需在相同窗口位置/时长补齐复测。

改前预览可执行文件SHA-256：`6c5f1ec7150ecaa0bf9c4be1404d2eb60e8cccc478285d88461e13a95971ebc4`；改后为`f299d39c2337021f740b1c426defbe3a413803ec42483e22b678cc2742736f4e`。原生UI已确认修复后初次抵达全文末尾；当时完整滚动检查尚未完成；后续UI观察和runtime补记见本文末尾，仍缺严格相同条件的内存复测。

还对改前实例成功执行20秒Animation Hitches采样，当时输出在`/tmp/snapai-roadmap-100k.trace`，现已丢失。导出的frame-lifetimes包含显示surface数据，尚未可靠归属到单一App/有效滚动区间，因此不报告60/120Hz达标率；不能把该表直接视为SnapAI逐帧耗时。

## 待完成的设备与效果验收

| 场景 | 下一步记录 | 当前边界 |
| --- | --- | --- |
| 10k/40k/100k 完成重排 | 用户上滚后的可见段落、完成前后位置偏移；表格和长代码横向滚动、复制原文 | 逻辑解析耗时不包含 SwiftUI 布局、渲染或高亮颜色属性组装 |
| 输入/结果窗 | 已有controller.show到就绪的30次P50/P95；新版身份定位复测及真实快捷键链路待执行 | 不以进程 main→ready 或controller调用代替全链路体验 |
| 帧率与主线程 | 60/120 Hz 下帧耗时分布、超 16.7/8.3 ms 比例、重排停顿和峰值内存 | 本文微基准不能证明稳定 60/120 FPS |
| 历史交互 | 连续输入、撤销/取消旧查询、最终查询发布时间与焦点 | 查询 CPU 耗时未包含 debounce、队列等待和 UI 发布 |
| 图片与生命周期 | 大图解码/OCR/删除峰值、30 次开关窗口、5–30 分钟空闲趋势 | 不以单次 RSS 判定泄漏或能耗 |
| 可访问性 | Reduce Motion/Transparency、增强对比度、VoiceOver、键盘滚动和表格阅读 | 有可访问名称不等于完成 VoiceOver 走查 |
| 固定任务与跨应用 | 翻译、润色、总结、代码解释、三类截图；浏览器/TextEdit/Electron/办公应用的取词与写回成功率 | 需真实应用与固定样本，不能由离线 fixture 推断 |

建立同设备、相同 build 配置的重复基线后再设置回归阈值。本轮优先保留原始样本与可复现命令。

## 2026-10-06 复核补记

用户解锁后继续检查了100k长文返回顶部、表格最右列可读、长代码横向滚动，以及模型元数据编辑的首开/保存/重开。新增真实窗口runtime覆盖10k/40k/100k首次到底、上下滚动复用、中段停留，以及宽代码/10列表格不撑宽主窗口，完整App runtime通过。这个回归验证行为和布局约束，不提供帧率。

一次clip直接滚动测试曾受SwiftUI保留旧ScrollViewReader定位意图影响；测试现用同一Reader明确上下端目标，并保留中部clip定位及全部位置断言。移除底部ready去重保护的临时版本能检出17条失败，当前保护版本通过。

原20秒trace及其TOC/帧导出临时文件在本次复核时已不存在，不能重做进程/surface归属审计；此前记录的全系统frame-lifetimes也未被当成SnapAI帧率。下一次录制需先证明process→surface→frame关联并持久保留经过裁剪的原始样本，再计算目标App的帧指标。

OCR专项发现两个独立问题：中文优先配置使清晰英文截图置信度不足，以及自动语言模型首次加载约27秒。现启用自动语言检测，保留0.5阈值与原图默认模式，45秒预算只影响主动等待OCR的模式。真实图回归通过，UI确认裁剪后重新识别；这不等于所有图片内容的OCR准确率或图片内存峰值已达标。

## 窗口延迟的持久基线

[`WINDOW_LATENCY_2026-10-06.json`](performance/WINDOW_LATENCY_2026-10-06.json) 保存四组各30次的成功原始样本、构建源码/二进制hash和环境信息，脚本为 `scripts/benchmark-window-latency.sh`。同一进程中首次组每次创建controller/window/hosting，复用组排除一次预热后重复打开同一窗口；均不代表OS冷启动。

| 窗口/方式 | 样本 | P50 | P95 |
| --- | ---: | ---: | ---: |
| quick / first-window | 30 | 191.565 ms | 212.039 ms |
| quick / reused-window | 30 | 170.157 ms | 172.095 ms |
| result / first-window | 30 | 193.980 ms | 201.794 ms |
| result / reused-window | 30 | 172.818 ms | 180.340 ms |

起点是实际controller.show调用前，模型与完成态fixture已准备。输入窗须可见/无遮挡、编辑器为firstResponder且插入内容被model接受；结果窗须指定Markdown标题和代码复制按钮的AX frame位于滚动viewport内。两者都需内容就绪后的didUpdate，以及alpha≥0.99连续两次probe；`interaction_ready_ms`另存。静态窗口fade结束后不保证额外didUpdate，因此不把该额外事件设为终点。

以上包含probe开销，但不包含硬件快捷键、系统启动、AI网络/流式生成或GPU/compositor scanout，不提供FPS。后来基准器加强为hosting的model/VM身份绑定，reuse用NSWindow对象身份；终点未改。新版已编译到 `.build/window-latency-identity-20261006-1`，构建日志见 [`window-latency-build.log`](performance/verification-20261006/window-latency-build.log)，尚未取得新版测量JSON，不能把旧样本称作新版实测。

OCR取消已由持久 `window-diagnostic.log` 的全量App runtime验证生命周期，`logic-final.log` 验证运行中与启动前取消；这不测量大图长期内存。历史搜索取消/分阶段发布已通过 [`history-final.log`](performance/verification-20261006/history-final.log) 的聚合逻辑回归（280个注册case，0 failures，3.713秒）和 [`history-app-build.log`](performance/verification-20261006/history-app-build.log) 的App构建（0.52秒）。首次Swift closure exclusivity编译失败日志 `history-initial-compile-failure.log` 保留，`shouldCancel @escaping`修复后才取得通过结果。未取得GUI连续输入到结果显示的P50/P95，因此上述缓存微基准仍只描述固定重复查询。

## 24 MP 大图的隔离解码与 OCR 内存采样（2026-10-06）

[`IMAGE_MEMORY_RASTER_2026-10-06.json`](performance/IMAGE_MEMORY_RASTER_2026-10-06.json) 保存 `scripts/benchmark-image-memory.sh docs/performance/IMAGE_MEMORY_RASTER_2026-10-06.json` 的30轮原始数据。Apple M4 / Mac16,10 上以独立 `swiftc -O` 进程直接编译真实 `ImageTextRecognition.swift`；fixture由另一个进程生成，固定6000×4000白底12行英文PNG（781,052 bytes），不读取用户图片、配置、历史或服务，不创建窗口。JSON含设备/系统/Swift版本、编译命令、源码/二进制/fixture SHA-256；测量结束后核对源码hash仍与工作区一致。

每轮依次读取Data、单独以ImageIO＋CGContext.draw强制生成并持有24 MP光栅、释放光栅、调用产品的 `recognizeText(in: Data)`（其解码也计入OCR耗时），然后释放本轮局部引用与autorelease pool。阶段数值为进程 `task_vm_info.phys_footprint`，peak为 `ledger_phys_footprint_peak` 的进程终身高水位，**不是各阶段独立峰值，也不是RSS**。每轮释放后再等1秒采样，第30轮后另等5秒。

| 阶段 | 进程内首次 | 后续29次P50 | 后续29次P95 |
| --- | ---: | ---: | ---: |
| 读取PNG Data | 0.106 ms | 0.720 ms | 0.789 ms |
| ImageIO＋完整光栅解码 | 76.815 ms | 112.886 ms | 127.634 ms |
| 产品Data→Vision OCR | 296.742 ms | 164.189 ms | 166.882 ms |

分位数使用nearest-rank。后续29次仅表示同进程重复调用，不等同于所有图片负载。30次均识别到固定英文正文，原始识别文本已保存；品牌字符串 `SnapAI` 被识别为 `SnapAl`，所以这不是逐字准确率通过证明。

进程baseline为1.657 MiB；首次强制光栅仍被持有时为95.626 MiB（截至该阶段peak187.173 MiB）。全程最高physical footprint为323.894 MiB。第2、20、30轮释放并等待1秒分别为108.501、112.830、113.894 MiB；最后额外等待5秒回落至73.300 MiB。数据包含显著异步回落，也存在高位缓慢上升，不能将全部残留直接认定为业务泄漏或系统缓存，不能由30轮证明长期不增长。尚未做worker autorelease pool干预、分配栈归因或5–30分钟空闲观察，因此未据此修改业务内存管理。

前两次探索原始文件 [`IMAGE_MEMORY_2026-10-06.json`](performance/IMAGE_MEMORY_2026-10-06.json) 和 [`IMAGE_MEMORY_30_2026-10-06.json`](performance/IMAGE_MEMORY_30_2026-10-06.json) 保留。其ImageIO probe没有明确持有完整光栅，不应与最终光栅阶段混用；首份6轮使用过严品牌字符串判定，`contains_fixture_text=false`不能视作没有识别到文字。首份OCR首次约24.98秒，而后两次新进程首次约0.30秒，说明新建进程并不能隔离系统语言模型缓存状态；这些运行不是OS冷启动A/B测试，也不计算通用优化比例。

**本采样仅覆盖独立Data解码和真实Vision OCR调用。** 它不覆盖QuickInput的NSImage压缩/预览、SwiftUI附件删除、在途OCR取消后的内存、窗口反复开关或真实上传量。已有QuickInput删除/替换/裁剪取消runtime验证的是生命周期行为，仍需解锁后测量实际UI图片添加/删除和长期资源趋势，才能判断报告第10节图片流程验收是否完整通过。
