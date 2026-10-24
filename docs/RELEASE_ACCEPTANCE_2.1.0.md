# SnapAI 2.1.0 验收记录

日期：2026-10-25。接续 `PROJECT_REVIEW_2026-10-02.md` 第 9、10 节。原始证据位于 [verification-20261025](performance/verification-20261025/)。

## 交付范围

完成报告 P0、P1 主路径和前序确认的 P2 持久会话、分支、可撤销上下文压缩。压缩由用户填写并确认摘要，不额外调用模型，原始轮次保留。会话仅本机保存，不进入 iCloud；历史保存关闭、仅元信息及高风险保护继续生效。文件检索与引用按需求排除；应用自动配置与逐段接受改写未纳入已确认范围。源文变更保护已实现。

新会话能力已接入结果窗口和历史窗口。恢复不请求网络、不沿用旧文档写回目标；原图及 OCR-only 提交状态分别恢复。实机预览已操作启用摘要、撤销、创建分支并观察写回按钮禁用，见 [界面证据](performance/verification-20261025/conversation-compression.png)。预览使用独立存储，不修改真实历史或供应商配置。

## 自动检查

- SwiftPM 逻辑回归通过，新增 7 个存储/分支/压缩/隐私测试已注册到正式 runner。
- App runtime 全量回归通过：会话实际 payload、恢复不联网、旧目标写回拒绝、OCR 生命周期、独立对照、Shortcuts 返回、五时点、30 次设置窗口生命周期及 10k/40k/100k 阅读往返。流式 runtime 也通过；为 hosted runner 的 run loop 增加了与主线程 Timer 同 cadence 的 fallback，正常 App 仍由 Timer 驱动。
- 首次失败记录 [app-runtime-initial.log](performance/verification-20261025/app-runtime-initial.log) 保留。修复当前回复尚未落盘导致追问遗漏，以及 Markdown 排版通知早于视图挂载导致首次末尾定位失败。
- 模块边界：97 个真实 Logic 源文件，0 symlink，0 App/core 重复类型。
- 本机发布预检包含供应链扫描、流式 runtime、macOS smoke、release 构建、macOS 14 deployment target、签名、安装 ZIP、manifest、SBOM 和 Sparkle appcast 校验。最终日志见同目录。

## 性能

固定设备、30 样本、nearest-rank 百分位；构建与源码 hash 在各 JSON metadata 中。单次基线不用于承诺稳定帧率。

| 场景 | P50 | P95 |
| --- | ---: | ---: |
| 首次输入窗 | 186.6 ms | 199.5 ms |
| 复用输入窗 | 169.5 ms | 172.9 ms |
| 首次结果窗 | 195.3 ms | 203.3 ms |
| 复用结果窗 | 173.5 ms | 176.6 ms |
| 10k 混合 Markdown 解析 | 1.82 ms | 2.18 ms |
| 40k 混合 Markdown 解析 | 7.35 ms | 8.04 ms |
| 100k 混合 Markdown 解析 | 18.29 ms | 18.92 ms |
| 50 条历史完整搜索，暖连接 | 31.4 ms | 31.8 ms |
| 200 条历史完整搜索，暖连接 | 120.2 ms | 122.1 ms |
| 500 条历史完整搜索，暖连接 | 293.6 ms | 303.3 ms |

窗口测量为真实 controller.show → 可输入/Markdown 可读、alpha≥0.99 且连续两次观察通过；控制器与 fixture 预先准备，同进程框架缓存保持温热，不包含硬件快捷键、系统进程启动、GPU 扫描和网络。解析在后台执行，解析耗时不等于 UI 帧耗时。历史完整搜索包含系统 embedding，词法结果先发布，不能把该指标冒充连续键入的端到端显示时延。原始数据见 [window-latency.json](performance/verification-20261025/window-latency.json) 与 [roadmap-performance.json](performance/verification-20261025/roadmap-performance.json)。

24MP 图片 30 轮隔离采样沿用 [已有大图证据](performance/IMAGE_MEMORY_RASTER_2026-10-06.json)：峰值约 324 MiB，释放等待后约 73 MiB。它不等于完整附件 UI 长期内存验证。

隔离 debug-preview 进程运行约 13 分与 25 分时，physical footprint 均为 43 MB、peak 45 MB，RSS 从约 52 MiB 到 55 MiB，采样 CPU 均为 0%。期间操作过会话 UI，两个离散快照不等于持续采样，也不是正式 release 的空闲内存承诺；证据为 `preview-memory-12min.md` 和 `preview-memory-25min.md`。

## 真实模型固定任务

使用仓库内虚构资料，未发送用户文档或密钥。通过产品 AIClient 流式请求，未改用户供应商配置。A 为已配置 `agnes-3.0-flash`，B 为已配置 `deepseek-v4`。每个模型执行 Q1a/Q1b/Q2/Q3/Q4 各一次；这是有限对照，未完成原验收设计的每配置 24 任务、两位独立评审盲评。原始正文 A001–A005、B001–B005 与请求记录均保留。评阅由本次执行 agent 按固定核对表完成，不称为人工盲评。

| 输出 | 请求结果 | 固定核对观察 |
| --- | --- | --- |
| A001、A002 | 完成 | 双向翻译保留关键数值、条件和文件标识；项目名使用一致转写 |
| A003 | 完成 | 只给一段正文，不满足两段；表达压缩且漏掉不可跳过检查，需修改 |
| A004 | 完成 | 缺部分截图/经费核对信息；不得视为全信息保真总结 |
| A005 | 截断、明确部分结果 | 三个调用的表格答案矛盾；达到 1000 output token 上限。保留错误，不把中途自我修正视为正确交付 |
| B001、B002 | 完成 | 翻译的关键事实和标识保持 |
| B003 | 完成 | 两段正文与三行动项；正文去空白 146 字符，满足 180 字符限制 |
| B004 | 完成 | 缺性能分母及经费数字，需补全 |
| B005 | 完成 | 三个调用的结果正确，说明短路和不修改输入；表格仅两列，要求为三列，需修正 |

两模型均为小样本，不能外推普遍正确率，不自动切换用户默认模型。两组共报告 input 3,894、output 3,811 token；另有探测请求 input 85、output 9 token。价格来源未能独立核实，因此不将 token 推导为实付金额，也不把缺价格当免费。请求限制与实际 usage 已保存；没有追加大规模质量调用或图片模型费用。

## 实机边界

跨应用固定 runner 每次验证 PID、bundleID、精确自有 fixture 标题、选区和目标身份；记录捕获方式、剪贴板和实际 transaction 回调。安全拒绝与成功写回分别记录。其初始化不是硬件全局快捷键链路。原始 JSON 与执行范围见同目录，不能把逻辑 fixture、少量实测或 AX 名称走查填成四应用 60 场景全通过。

本轮 TextEdit/Word 共记录 20 次 runner 尝试：18 次达到对应预期，另有前台身份变化与测试 go-marker 等待超时各 1 次环境阻塞。18 次分为 9 次取词、3 次实际写回、6 次按预期保护拒绝（剪贴板竞争或同范围源文变化）。未观察到误写，但样本不覆盖所有控件；详见 `cross-app-summary.json`。Word 使用 RTF 兼容模式，选区只替换固定文本，不能代替富文本样式还原的完整验收。

浏览器打开本地 fixture 被工具 URL 策略拒绝，未绕过策略，记为未完成；未找到本次指定的已安装 Electron 编辑器，未测。硬件快捷键链路、四应用完整 60 场景和系统 Shortcuts 下游串联尚无完整本轮实测证据。

macOS 14/15、120 Hz、完整 VoiceOver/对比度人工检查、全部浏览器富文本和 Electron 控件仍未完整实测。当前设备所得结果是发布基线及明确限制，不作“任意应用”“稳定 60/120 FPS”或“所有模型质量达标”承诺。
