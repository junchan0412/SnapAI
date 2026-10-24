# 报告路线实施与验收清单

更新：2026-10-25。依据 `PROJECT_REVIEW_2026-10-02.md` 第 9、10 节，在原工作区改动上继续实施。报告保留为 10 月 2 日基线；前序记录描述当时状态，本轮接续和发布结果见文末。

总目标继续覆盖报告第9、10节，尚未宣布完成。本轮执行报告的“可信维护版”“截图与阅读增强版”，并选取真正双模型、可组合 Shortcuts 两项场景效率能力，并补齐P1用量统计。P2 遵守报告“验证需求后推进”的前提，不将未实现能力列为完成。

## 功能范围

| 项目 | 当前状态 | 实现与证据 |
| --- | --- | --- |
| P0 对照入口与文档真实性 | 已实现 | 对照先选择模型/确认输入再发两条独立请求；README统一Sparkle更新说明、部分英文本地化边界；开发功能标明未发布 |
| P0 原图保留、OCR 三种模式、附件重发 | 已实现 | `QuickInputImageInput`快照、OCR generation隔离、任务取消、失败保留；原图/OCR文字/图文一起；换动作/语言/原文重发保留imageData；首次、追问及重试均发送已确认的完整messages快照，预览/风险含历史图片和sourceContext |
| P0 生成/展示状态分离、立即显示全文 | 已实现 | `isGenerating`与`isStreaming`区分；网络结束记录成功/历史；追问不等动画；跳过动画不标partial；关闭时取消待执行自动写回 |
| P0 Reduce Motion、基线口径 | 已实现 | 打字机/提示/快捷键录制脉冲遵守系统偏好；最快档不高于60Hz timer、完成积压自适应收尾；preview明确debug-preview/release-preview及fixture |
| P1 区域/窗口截图、发送前裁剪 | 已实现 | 系统选区/窗口/主屏幕；确认裁剪实际像素并重新OCR；取消与失败保留草稿；像素方向和边界回归 |
| P1 Markdown 表格、代码、阅读位置 | 已实现，UI验收另列 | 表格对齐/横滚、代码基础高亮/横滚、原编号/嵌套/任务列表；按需block布局和独立末尾锚点；完成后恢复正文相对位置，用户继续滚动取消恢复；不是逐字锚点 |
| P1 模型能力与价格覆盖 | 已实现 | 任意别名的视觉/推理/上下文、USD输入输出价格与来源；路由与诊断共用能力快照；导入/同步/刷新保留覆盖；修复编辑sheet首次空白，实际填写/保存/重开验证通过 |
| P1 真正双模型与选优 | 已实现 | 两个client独立输出/TTFT/耗时/取消/错误；选中并复制；部分输出明确标记；不自动写回或替换主会话 |
| P1 Shortcuts 正文与结构化错误 | 已实现，系统发现待验收 | 独立VM复用隐私/脱敏/路由；返回完整正文或JSON稳定错误码，超时/取消；等待从隐私确认后开始 |
| P1 TTFT/token/费用/预算 | 已实现 | OpenAI/Anthropic真实usage，含finish_reason尾部；缺失值不冒充0；按请求时单价估算、按日聚合、月预算提醒；API时间不含动画；兼容开关可关闭usage参数 |
| standalone runner 与关键回归 | 已修复 | 条件导入支持standalone；新增附件/OCR/裁剪/元数据/表格/usage/双模型/Shortcuts回归，App runtime脚本真正编译并调用新fixture |
| 测量驱动的历史搜索改进 | 已实现，逻辑回归与App构建通过 | 重复查询的系统距离有界内存缓存；新实现取消旧查询、先发布词法/FTS再补语义结果；保持最终阈值/排序；系统单次distance调用仍不可抢占 |
| P2 应用/项目专属配置 | 需求待验证 | 当前可手选动作/模型/上下文；待确定自动推荐规则及显式覆盖方式 |
| P2 分段接受改写与源文校验 | 源文校验已实现；分段接受需求待验证 | 恢复选区前及粘贴前检查原range/text、当前选区、PID、AX元素/窗口和可读document身份；已知变化拒绝，无法核验时明确二次确认；逐段选择未实现 |
| P2 持久会话、分支、上下文压缩 | 需求待验证 | 当前仍为轻量历史；跨重启附件/会话恢复与分支未实现 |
| P2 文件检索与引用 | 需求待验证 | 需先确定真实资料类型、权限和引用需求；未接文件RAG |

## 验收证据

下列为本轮实际取得的自动检查和固定设备测量证据。真实模型回答、跨应用写回、系统Shortcuts发现不由本地fixture替代。

- SwiftPM debug 构建：通过；正式release与隔离release-preview构建通过。
- 逻辑测试：2026-10-06 11:44 的 SwiftPM 聚合 XCTest 通过（0 failures，3.594秒），持久日志为 [`logic-final.log`](performance/verification-20261006/logic-final.log)。包含真实图、空白图、OCR超时/运行中及启动前取消、写回源校验；之后的历史搜索取消修改已完成复验：[`history-final.log`](performance/verification-20261006/history-final.log) 记录12:31聚合XCTest通过（280个注册case，0 failures，3.713秒），[`history-app-build.log`](performance/verification-20261006/history-app-build.log) 记录App debug构建通过（0.52秒）。
- 模块边界：95个真实Logic源文件、0 symlink、0 App/core重复类型。
- 流式 runtime：通过，含尾部usage兼容、有界等待、Anthropic最终用量与取消。
- App runtime：通过，包含独立对照、Shortcuts、五个时点、30次设置窗开关和原有取消/错误/写回策略。复验中发现并修复本地优先可能被云模型高分反超的问题。2026-10-06已完成全量复跑，含最终LazyVStack/末尾锚点、完整payload隐私、本地预检跳过/动作绑定/无本地候选，以及10k/40k/100k往返阅读和代码/表格横滚回归。
- 性能原始数据和测量口径：[性能验收记录](ROADMAP_PERFORMANCE_2026-10-04.md)。
- 固定任务、评分、跨应用场景与未实测记录：[功能验收集](ROADMAP_ACCEPTANCE_2026-10-04.md)。

## 第 10 节覆盖与限制

| 范围 | 本轮处理 | 尚待取得的证据 |
| --- | --- | --- |
| 固定功能任务集 | 固定文本和本地HTML图表/界面/纯文字输入、保真/格式/修改量评分 | 指定真实模型后盲评，不消费真实API费用作为离线验收 |
| 四类应用取词写回 | 统一AX/复制/焦点/源文修改/剪贴板恢复测试表 | 浏览器、TextEdit、Electron、办公应用逐项实际成功率 |
| 五个时点 | 请求开始/首正文或思考/网络结束/展示结束/Markdown ready独立记录，可复制完整诊断 | 实际供应商TTFT和各阶段P50/P95 |
| 长文10k/40k/100k | 固定混合Markdown、优化解析P50/P95、release-preview；100k布局/初次末尾定位与内存快照 | UI帧耗时/主线程停顿/阅读位置误差；解析耗时不等于FPS |
| 历史50/200/500 | 读取/FTS/实际完整搜索的冷暖连接P50/P95 | 连续输入到可见结果的端到端时延与取消体验 |
| 大图/OCR | 模式与裁剪像素一致性、识别竞态回归；24MP隔离进程30轮解码/OCR/释放采样 | QuickInput预览/压缩、UI删除及在途取消后的长期内存趋势 |
| 窗口生命周期 | App runtime 30次设置窗开关/hosting释放；隔离preview取得4分钟与15分钟两个独立实例快照（末次邻近锁屏） | 遮挡、低功耗及5–30分钟稳定趋势 |
| 可访问性 | Reduce Motion实现与timer回归、既有键盘/AX smoke | Reduce Transparency/增强对比度/VoiceOver完整人工走查及macOS14/15回退 |

单次测量只作为当前设备基线。下一轮复测使用相同fixture、编译配置与源码hash，再决定性能回归阈值。

GUI复验仍在继续，瞬时锁屏状态以各次执行记录为准。P2需求范围仍待明确，真实模型质量、四类外部应用完整写回矩阵、完整VoiceOver/低版本系统与应用归属帧指标仍未完成，总目标保持active。

## 2026-10-05 至 06 补充修复与验证

- 预检跳过本地路线、动作绑定供应商、缺Key/禁用/未配置本地模型都不能绕过云端边界；自动本地优先模式在实际启动任何云请求前阻止，需关闭自动路由并明确手选云模型后重试。
- 发送前预览由完整消息生成，包含system、历史轮次、sourceContext及图片；实际请求直接使用已批准的快照。追问与重试也会按当前隐私配置重新准备。
- 模型编辑sheet改用一次性的“供应商＋模型”选择状态；原生UI已验证首开、填写32k上下文和fixture单价、保存及重开保留。
- Markdown底部锚点每份正文只通知一次；真实NSHostingView回归覆盖10k/40k/100k上下端、中段停留、block复用、横滚不撑宽。临时移除保护后检出17条失败，当前版本全部通过。
- 清晰英文图在固定中文优先OCR下平均置信度0.433；启用自动语言检测后为1.0，未降低0.5阈值，中文fixture同时通过。模型首次加载实测27.08秒，默认等待预算45秒，超时取消任务；无可靠文字/超时/解码/系统错误分别保留。
- 实际图片UI验证：1600×1066原图保留，三模式说明与内容切换正确；拖动裁剪到519×252后使用新图，OCR从78字刷新为66字，保留“图文一起”；删除附件同时清除OCR并禁用空提交。此为工作流验证，不代表逐字OCR质量满分。
- OCR lifecycle：删除、有效换图、成功裁剪和模型释放均取消旧任务，隐藏窗口保留草稿与OCR；runtime先等待识别闭包启动再取消，覆盖旧结果不得发布。Vision运行中每至多50ms检查取消并调用request.cancel；单次系统调用的退出时间仍由系统决定。
- App runtime本轮首次失败日志保留为 [`app-runtime.log`](performance/verification-20261006/app-runtime.log)。size与Escape测试改用hosting的VM身份定位窗口，未放宽断言/超时或改业务关闭逻辑；修正后全量 [`window-diagnostic.log`](performance/verification-20261006/window-diagnostic.log) PASS，包含新增OCR lifecycle。
- 写回还增加粘贴前剪贴板changeCount检查，竞争时保留新剪贴板且不以fallback复制覆盖；成功后保留可验证snapshot用于撤销。Diff左列明确为“捕获时原文”。
- 四组窗口延迟每组30次已保存，详见性能记录；以model/VM精确身份绑定的新版基准器已编译，尚待执行。
- 旧 `/tmp` 跨应用原始日志已丢失，只能保留当时观察，不能据此填满当前验收矩阵。新runner/fixture保存在 `.build`，新原始日志写入 `docs/performance/verification-20261006/`；完整复验待完成。
- 真实模型探测：Apple Foundation Models报告 `deviceNotEligible`；Ollama与LM Studio默认本地端点当次不可达，不代表全部自定义端点不存在。真实质量评分仍待指定可用供应商/模型和费用范围。

- 历史搜索首次测试遇到Swift closure exclusivity编译错误，原日志保留为 [`history-initial-compile-failure.log`](performance/verification-20261006/history-initial-compile-failure.log)；`shouldCancel`改为`@escaping`后逻辑回归及App构建通过。连续输入到可见结果的GUI端到端P50/P95仍未取得。

## 2026-10-06 裁剪可访问性与大图采样

- 裁剪选区原来只能拖动；现增加左/上/宽/高原生像素 Stepper，即时更新同一选区，并提供“选择全图”。像素与显示坐标转换消除整数边界的浮点表示误差，保留真实分数边缘向外取整，支持有效的1像素裁剪。逻辑回归和App构建通过，见 [`crop-accessibility-logic.log`](performance/verification-20261006/crop-accessibility-logic.log) 与 [`crop-accessibility-build.log`](performance/verification-20261006/crop-accessibility-build.log)。真实键盘、VoiceOver和布局仍待桌面验收。
- 24MP图片的30轮隔离进程采样保存于 [`IMAGE_MEMORY_RASTER_2026-10-06.json`](performance/IMAGE_MEMORY_RASTER_2026-10-06.json)。29次暖OCR P50/P95为164.189/166.882ms；全程physical footprint peak为323.894MiB，最后释放后113.894MiB，额外等待5秒后73.300MiB。存在回落，不能直接判定持续泄漏或缓存归因；不覆盖QuickInput完整UI生命周期。详细口径见性能文档。
- 图像测量于12:58:41结束；裁剪测试日志于12:59:20创建，未与该轮编译重叠。桌面工具本轮仍报告Mac锁定，跨应用、新版窗口延迟及完整可访问性验收尚未执行。

## 2026-10-06 13:04 阻塞复核

本次CUA再次返回Mac locked，已连续三个goal轮次出现同一条件；前两轮仍完成了历史搜索、裁剪控件和大图测量。本轮核查后没有可独立推进的、证据明确的必要实现缺口，也没有仍在运行的验证任务。默认Ollama/LM Studio端点复查仍不可达，见 [`local-model-endpoints-recheck.json`](performance/verification-20261006/local-model-endpoints-recheck.json)。这不排除用户另有自定义模型端点。

目标进入blocked等待条件，未完成且未缩减范围。解除条件后继续：

1. 桌面解锁：跨应用矩阵、快捷键/Shortcuts、新版窗口延迟、连续搜索交互、帧/主线程性能、图片UI生命周期及键盘/VoiceOver验收。
2. 指定可用真实供应商/模型和费用范围：固定任务质量、真实请求五时点与上传量验收；无需在聊天发送API Key。
3. 明确P2需求：应用/项目配置、分段接受、持久会话分支压缩、文件检索引用；原报告要求先验证需求。
4. macOS14/15和不同刷新率的实测需对应设备/环境，不能以当前设备的构建或微基准替代。

## 2026-10-25 / 2.1.0

前序确认需要持久会话、分支和上下文压缩，文件检索与引用排除本轮。

存储草稿已接入结果窗口与历史窗口。会话恢复保留全部轮次、模型信息、部分结果标记和原图；OCR-only 本机原图与实际请求图片分开。恢复不发请求、不绑定旧文档；分支保留原会话；摘要由用户确认后启用并可撤销。存储受历史开关、上限、仅元信息及高风险保护约束。

新增 App runtime 检查真实追问 payload、分支独立、摘要撤销、恢复不联网、恢复字数和旧文档写回拒绝，并将前序 7 个会话存储测试接入正式逻辑 runner。首次回归发现尚未落盘回复遗漏及 Markdown 定位竞态，修复后复跑通过；首次失败记录保留。隔离预览也使用独立历史、会话和密钥缓存，避免测试数据进入真实配置。

最终范围、回归日志、真实模型结果、性能测量及发布证据见 [2.1.0 验收记录](RELEASE_ACCEPTANCE_2.1.0.md)。之前的锁屏和模型不可用记录只描述当时状态。
