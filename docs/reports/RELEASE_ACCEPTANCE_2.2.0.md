# SnapAI 2.2.0 验收记录

日期：2026-11-01 至 2026-11-02（Asia/Shanghai）。本版接续 [2026-10-25 项目检查](PROJECT_HEALTH_2026-10-25.md) 中的编译 warning 与实机验证事项；此前能力和历史样本见 [2.1.0 验收记录](RELEASE_ACCEPTANCE_2.1.0.md)。本轮原始证据位于 [verification-20261101](../performance/verification-20261101/)。

## 基线与当前结论

开始验证的源码基线为 `db85b646419e80d1c8c56ee7cb8b5d5d6eeb317c` 加本轮 working tree，`Resources/Info.plist` 版本为 **2.2.0**。各日志取得后仍有拖排实现修改，不能把较早构建的通过结果直接归到最终源码。最终交付基线应以 `v2.2.0` tag、release manifest 和 SBOM 记录为准，下表在最终发布后补齐。

| 项目 | 当前状态 |
| --- | --- |
| 最终源码 commit / `v2.2.0` tag | 待填 |
| 最终 release 预检日志 | 待运行、待填 |
| CI run / commit / 结果 | 待运行、待填 |
| ZIP、manifest、SBOM、Sparkle appcast 校验 | 待最终打包验证、待填 |

当前原生拖排、侧栏重排与图标库 GUI 验收已通过；逻辑、流式 runtime 和网站图标探测已有通过记录。删除临时诊断 trace 后源码已完成 headless 构建；最终 App runtime、clean release 预检和同 HEAD CI 在发布前继续验证，状态以下表为准。

本机 `sw_vers` 返回 macOS **27.2**（build `26B123`）。App runtime 使用项目源码构建的独立测试 app 和隔离 fixture；GUI 记录使用项目 Debug 构建的 `SnapAI Preview`，不是 `/Applications` 中的旧版 SnapAI。测试与预览不借用用户的真实供应商、历史或图标配置。Debug 预览记录也不作为最终 Release 性能或兼容性数据。

## 交付范围

- 供应商、动作卡片使用左侧拖排把手，设置侧栏导航也可调整顺序并保存；移除原上移、下移按钮。
- 供应商根据 API 端点推断网站并获取 favicon，也可指定网站、使用内置符号或导入本地图片；图标库支持复用、持久保存和删除。
- 设置、结果、快捷提问与命令面板采用透景材质；macOS 26 及以上卡片继续使用 Liquid Glass，旧系统按原生毛玻璃回退。
- 打开设置或引导主面板时显示 Dock，关闭最后一个主面板后隐藏；最小化保留 Dock，菜单栏、快捷键和后台请求继续运行。旧 Dock 手动开关移除，旧 URL 入口对应主面板的打开与关闭。
- 提供 light/dark 双软件图标，接入 Dock、设置侧栏和欢迎界面，随系统外观切换。
- 修复旧报告指出的 AXUIElement 可选值强转与异步 OCR 测试 semaphore warning，保留类型核验和取消测试。

交付内容说明已实现的范围，验证状态以下文为准；本版不将低版本系统、完整跨应用操作和 iCloud 双机同步归入已通过项。

## 已取得的自动检查证据

| 检查 | 结果与覆盖范围 | 证据及边界 |
| --- | --- | --- |
| SwiftPM 逻辑回归 | 通过；最终聚合 XCTest 0 failures，耗时 5.095 秒，包含真实 OCR 与取消检查，本次日志没有 OCR `SKIP` | [logic-final.log](../performance/verification-20261101/logic-final.log)。日志中的存储失败信息来自故障 fixture，不是测试执行失败；不把一个聚合 XCTest 当作只有一项逻辑检查 |
| App runtime | 先前构建通过；最终原生 receiver 版本在锁屏会话中重跑未通过，不能替代解锁后的完整验收 | [app-runtime.log](../performance/verification-20261101/app-runtime.log) 来自旧 `DropDelegate`；最终失败对照见下文。窗口创建、Dock 生命周期、图标库和排序算法无失败报告；Escape 焦点/AX 与动画等待需在可激活会话重验 |
| 流式 runtime | 通过；覆盖取消、重启、请求快照、部分失败、空闲 Timer 与 Markdown 合并 | [streaming.log](../performance/verification-20261101/streaming.log)。slow-gap timeout 为预期探测结果，未承诺所有远端请求成功 |
| 网站图标探测 | 通过本地真实 HTTP fixture 与至少一个公开网站获取；Apple 网站本次成功返回可解码图标 | [provider-icon-probe-results.json](../performance/verification-20261101/provider-icon-probe-results.json)、[HTTP 请求记录](../performance/verification-20261101/provider-icon-probe-http.json)。含源码与构建对象 hash；这是图标获取探测，不是模型 API 测试 |
| 供应链扫描 | 当前依赖扫描未发现问题，SwiftPM 仅 Sparkle 2.9.6 | [supply-chain.log](../performance/verification-20261101/supply-chain.log)。结果限于扫描到的依赖，不代替全面安全审计 |
| 编译与签名构建 | 较早工作区构建通过，发行构建使用 `SnapAI Local Signing`，声明 macOS 14 deployment target | [swift-build.log](../performance/verification-20261101/swift-build.log)、[release-build.log](../performance/verification-20261101/release-build.log)。不是最终源码的 clean release 预检，也未据此宣布最终 ZIP、更新 feed 已验证 |

窗口 runtime 已确认：设置与引导并存时，关闭其中一个仍保留 Dock；全部主面板关闭后改为 accessory 且进程继续运行；快捷面板不会单独建立主面板 Dock 入口。这里验证的是项目 AppKit 生命周期和 activation policy，不将它替代所有用户操作路径的 GUI 验收。

图标库 runtime 覆盖导入后原文件删除仍可读取、重新创建库后可复用、非正方形图片保持比例并留透明边、删除释放缓存及无效图片拒绝。网站探测覆盖相对 favicon URL、页面和图片重定向、多次无效声明后的 `/favicon.ico` 回退、并发请求合并、正/负缓存及隐私模式不发新请求。本地 HTTP 请求记录未见 Authorization 或 Cookie header；网站仍可观察普通图标资源请求。本地图标只保存文件引用，未在本轮进行双机图片同步验证。

首次 App runtime 失败日志 [app-runtime-initial-failure.log.gz](../performance/verification-20261101/app-runtime-initial-failure.log.gz) 保留。最终重跑的 [首轮焦点失败](../performance/verification-20261101/app-runtime-final-initial-failure.log.gz)、[regular 前置对照](../performance/verification-20261101/app-runtime-regular-fixture-failure.log.gz) 和 [顺序隔离对照](../performance/verification-20261101/app-runtime-order-isolation-failure.log.gz) 也保留；本机随后确认 `IOConsoleLocked=Yes`、`CGSSessionScreenIsLocked=Yes`，对应结果窗 inactive/key=false/occluded，第三轮动画还停在 alpha=0。未保留无效的测试顺序或 policy 调整，原有焦点、AX、popover 和 Escape 断言不跳过；解锁会话后需重新验证最终 runtime。

## GUI 验收证据

已有 [供应商页截图](../performance/verification-20261101/provider-light.jpg)、[动作页截图](../performance/verification-20261101/actions-light.jpg) 与 [light](../performance/verification-20261101/app-icon-light-preview.png) / [dark](../performance/verification-20261101/app-icon-dark-preview.png) 图标预览。截图与 AX 树能记录界面状态，不能证明拖排动作改变了顺序。

早期 [供应商拖排记录](../performance/verification-20261101/ui-provider-drag.txt)、[侧栏拖排记录](../performance/verification-20261101/ui-sidebar-drag.txt) 和 [拖排诊断](../performance/verification-20261101/ui-drag-diagnostic.log) 保留为失败诊断，不能归为最终实现的通过证据。独立 [NativeDragProbe.swift](../performance/verification-20261101/NativeDragProbe.swift) 和 [native-drag-probe.log](../performance/verification-20261101/native-drag-probe.log) 也仅用于原生拖放链路对照。

最终供应商和动作采用原生拖动 source 与 receiver，侧栏保留原生 List `onMove`。[gui-native-final-events.log](../performance/verification-20261101/gui-native-final-events.log) 记录了供应商两次、动作两次实际 payload/perform 和 source `end=1`；取消为 `end=0` 且未 perform。GUI 记录取得后仅删除临时 trace，再执行 headless 构建和最终 runtime；未改变重排算法与 Binding 接口。

本机测试方法为 `Cua.drag` 后在目标 padding 补一次 `click(duration: 500)` 以稳定释放。AX 前后顺序、实际 payload 和 session end 共同证明上述动作通过；**裸 `Cua.drag` 的释放与指针恢复可靠性仍未证实**，不将工具时序边界记录为正常物理鼠标失败或已验收的裸手势。Preview 使用隔离 fixture，退出后删除自身 suite，不能用它证明正式配置跨进程重启；保存与重新加载的依据来自逻辑和 App runtime。

| 当前实现的验收项 | 状态 / 最终证据 |
| --- | --- |
| 供应商左侧把手双向拖排、取消及卡片操作 | 通过；[下排](../performance/verification-20261101/provider-down.ax.txt)、[上排](../performance/verification-20261101/provider-up.ax.txt)、[取消](../performance/verification-20261101/provider-cancel.ax.txt) 与 [最终状态](../performance/verification-20261101/provider-final.ax.txt)；OpenAI 从第一移至第三再恢复，取消无改动，[展开](../performance/verification-20261101/provider-expanded.ax.txt) 仍对应 OpenAI |
| 动作双向拖排、快捷键与编辑对象保持 | 通过；[下排](../performance/verification-20261101/actions-down.ax.txt)、[上排](../performance/verification-20261101/actions-up.ax.txt) 与 [展开](../performance/verification-20261101/actions-expanded.ax.txt)；提问从第一移至第三再恢复，Prompt 与 `⌥A` 保留；不替代硬件快捷键触发测试 |
| 设置侧栏双向拖排、导航选择与保存 | GUI 通过；[下排](../performance/verification-20261101/sidebar-down.ax.txt)、[上排](../performance/verification-20261101/sidebar-up.ax.txt) 中 AI 模型往返重排，选择与详情仍正确；JSON 保存/重新加载由逻辑回归覆盖 |
| 图标库导入、跨供应商复用、应用与删除 | 通过；[导入](../performance/verification-20261101/provider-icon-import.ax.txt)、[复用](../performance/verification-20261101/provider-icon-reuse.ax.txt)、[应用](../performance/verification-20261101/provider-custom-icon-applied.ax.txt)、[清理](../performance/verification-20261101/provider-icon-test-cleanup.ax.txt)；只删除测试副本并恢复默认图标 |
| light/dark 图标在 Dock、侧栏、欢迎界面接入 | 素材与本机 Preview 显示已有记录；发行 bundle 四资源一致性在最终预检核对，不宣称低版本或所有视觉路径专项测试完成 |
| 主面板开/关、最小化与后台持续运行 | 由实际 WindowCoordinator/AppKit 生命周期 runtime 验证；不替代全部用户操作路径的专项 GUI 走查 |
| 透景材质与系统降低透明度偏好 | 本机 Preview 截图及透明窗口配置已有验证；Reduce Transparency 和 macOS 14/15 回退仍未完成专项实测 |
| 当前排序实现的 App runtime 重跑 | 锁屏会话下重跑未通过；除 Escape 焦点/AX 及动画等待外无失败报告，解锁后须重新完整验证，不将局部结果记作整体验收通过 |

## 兼容性与未验证范围

最低系统声明仍为 macOS 14，预编译发行包面向 Apple Silicon。macOS 14/15 真机毛玻璃回退未测；本机现代系统结果不能代替低版本兼容性。稳定自签名不等于 Apple Developer ID 或 notarization，首次手动安装继续遵循 [README](../../README.md) 的 quarantine 处理说明。

本轮没有完成四应用全场景的取词、硬件全局快捷键和写回验收，也没有重测真实模型质量；相关限制继续沿用 2.1.0 验收记录，先前有限 TextEdit/Word 样本不计为本轮全面通过。iCloud 配置同步的正式 entitlement、双机冲突处理与自定义图标缺失回退未做完整双设备验收，本地图标图片不随配置同步。

完整 VoiceOver、键盘读序、对比度、Reduce Transparency、120 Hz 帧预算及完整附件 UI 长期内存仍未完成专项实测。本轮没有新增可用于对外承诺的帧率、耗时或内存基线。
