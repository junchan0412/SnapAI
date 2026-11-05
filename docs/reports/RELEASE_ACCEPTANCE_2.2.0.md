# SnapAI 2.2.0 验收记录

日期：2026-11-01 至 2026-11-05（Asia/Shanghai）。本版接续 [2026-10-25 项目检查](PROJECT_HEALTH_2026-10-25.md) 中的编译 warning 与实机验证事项；此前能力和历史样本见 [2.1.0 验收记录](RELEASE_ACCEPTANCE_2.1.0.md)。GUI 与图标探测证据位于 [verification-20261101](../performance/verification-20261101/)，最终发布预检见 [verification-20261103](../performance/verification-20261103/)，线上资产与更新通道记录见 [verification-20261105](../performance/verification-20261105/)。

## 发布基线与结论

正式版本为 **2.2.0**，发布源码为 `e9414b161e04350bd67b9678bdc453d73a3dcfd7`，与 `v2.2.0` tag 和发行 SBOM 的 `git.commit` 一致。[GitHub Release](https://github.com/junchan0412/SnapAI/releases/tag/v2.2.0) 于 2026-11-03 00:54（Asia/Shanghai）发布。

| 项目 | 结果与证据 |
| --- | --- |
| 最终源码 commit / `v2.2.0` tag | `e9414b161e04350bd67b9678bdc453d73a3dcfd7` |
| 最终 release 预检 | 通过；2026-11-03 执行 `scripts/preflight-release.sh --require-clean --require-synced`，见 [完整日志](../performance/verification-20261103/preflight-release.log) |
| 同发布源码 CI | [push run 41350431521](https://github.com/junchan0412/SnapAI/actions/runs/41350431521) 与 [手动 run 41350569558](https://github.com/junchan0412/SnapAI/actions/runs/41350569558) 均为 success，HEAD 均为上述 commit |
| ZIP、manifest、SBOM、Sparkle appcast | 最终预检通过签名、版本、安装包、SBOM 来源和 appcast 校验；[11 月 5 日记录](../performance/verification-20261105/release-channel.txt) 确认五项线上资产与本机预检产物逐字节一致，`releases/latest` 返回同一 appcast |
| 发布后更新窗口 | 通过；已安装 2.2.0 返回最新版提示，用户目视确认窗口可见，`SULastCheckTime` 更新；见 [更新通道记录](../performance/verification-20261105/release-channel.txt) |

供应商和动作原生拖排、侧栏重排与图标库 GUI 验收通过；发布源码的逻辑、真实 OCR、流式 runtime、完整 App runtime 和签名发布预检均通过。

本机 `sw_vers` 返回 macOS **27.2**（build `26B123`）。App runtime 使用项目源码构建的独立测试 app 和隔离 fixture；GUI 记录使用项目 Debug 构建的 `SnapAI Preview`，不是 `/Applications` 中的旧版 SnapAI。测试与预览不借用用户的真实供应商、历史或图标配置。Debug 预览记录也不作为最终 Release 性能或兼容性数据。

11 月 5 日在已安装的 `/Applications/SnapAI.app` 2.2.0 上执行「检查更新…」。其可执行文件、Info.plist、签名资源清单及四项图标资源与发布 ZIP 一致。Sparkle 返回「您使用的就是最新版！SnapAI 2.2.0 是当前的最新版本」，用户目视确认提示窗口可见；[对话框 AX 记录](../performance/verification-20261105/sparkle-update-window.ax.txt) 已保存，`SULastCheckTime` 更新为 2026-11-05 15:00:46（Asia/Shanghai）。

## 交付范围

- 供应商、动作卡片使用左侧拖排把手，设置侧栏导航也可调整顺序并保存；移除原上移、下移按钮。
- 供应商根据 API 端点推断网站并获取 favicon，也可指定网站、使用内置符号或导入本地图片；图标库支持复用、持久保存和删除。
- 设置、结果、快捷提问与命令面板采用透景材质；macOS 26 及以上卡片继续使用 Liquid Glass，旧系统按原生毛玻璃回退。
- 打开设置或引导主面板时显示 Dock，关闭最后一个主面板后隐藏；最小化保留 Dock，菜单栏、快捷键和后台请求继续运行。旧 Dock 手动开关移除，旧 URL 入口对应主面板的打开与关闭。
- 提供 light/dark 双软件图标，接入 Dock、设置侧栏和欢迎界面，随系统外观切换。
- 修复旧报告指出的 AXUIElement 可选值强转与异步 OCR 测试 semaphore warning，保留类型核验和取消测试。

## 自动检查证据

| 检查 | 结果与覆盖范围 | 证据及边界 |
| --- | --- | --- |
| SwiftPM 逻辑回归 | 通过；发布预检的聚合 XCTest 0 failures，耗时 5.172 秒，包含真实 OCR 与取消检查，日志没有 OCR `SKIP` | [最终预检日志](../performance/verification-20261103/preflight-release.log)。本机预检强制 `SNAPAI_REQUIRE_SYSTEM_OCR=1`；存储失败信息来自故障 fixture |
| App runtime | 通过；发布源码覆盖窗口与 Dock 生命周期、图标库、排序、结果焦点与 Escape、popover、动画等待、独立模型对照和 Shortcuts | [最终预检日志](../performance/verification-20261103/preflight-release.log) 的 `PASS App runtime smoke` |
| 流式 runtime | 通过；覆盖取消、重启、请求快照、部分失败、空闲 Timer 与 Markdown 合并 | [最终预检日志](../performance/verification-20261103/preflight-release.log)。slow-gap timeout 为预期探测结果 |
| 网站图标探测 | 通过本地真实 HTTP fixture 与至少一个公开网站获取；Apple 网站本次成功返回可解码图标 | [provider-icon-probe-results.json](../performance/verification-20261101/provider-icon-probe-results.json)、[HTTP 请求记录](../performance/verification-20261101/provider-icon-probe-http.json)。含源码与构建对象 hash；这是图标获取探测，不是模型 API 测试 |
| 供应链扫描 | 发布预检未发现依赖问题，SwiftPM 仅 Sparkle 2.9.6 | [最终预检日志](../performance/verification-20261103/preflight-release.log) |
| 编译与签名构建 | 发布源码构建通过，发行构建使用 `SnapAI Local Signing`，声明 macOS 14 deployment target；签名及解压安装包校验通过 | [最终预检日志](../performance/verification-20261103/preflight-release.log)，含 App Intents 元数据提取、独立配置启动与正常退出 |

窗口 runtime 已确认：设置与引导并存时，关闭其中一个仍保留 Dock；全部主面板关闭后改为 accessory 且进程继续运行；快捷面板不会单独建立主面板 Dock 入口。这里验证的是项目 AppKit 生命周期和 activation policy，不将它替代所有用户操作路径的 GUI 验收。

图标库 runtime 覆盖导入后原文件删除仍可读取、重新创建库后可复用、非正方形图片保持比例并留透明边、删除释放缓存及无效图片拒绝。网站探测覆盖相对 favicon URL、页面和图片重定向、多次无效声明后的 `/favicon.ico` 回退、并发请求合并、正/负缓存及隐私模式不发新请求。本地 HTTP 请求记录未见 Authorization 或 Cookie header；网站仍可观察普通图标资源请求。本地图标只保存文件引用，未在本轮进行双机图片同步验证。

## GUI 验收证据

已有 [供应商页截图](../performance/verification-20261101/provider-light.jpg)、[动作页截图](../performance/verification-20261101/actions-light.jpg) 与 [light](../performance/verification-20261101/app-icon-light-preview.png) / [dark](../performance/verification-20261101/app-icon-dark-preview.png) 图标预览。截图与 AX 树能记录界面状态，不能证明拖排动作改变了顺序。

供应商和动作采用原生拖动 source 与 receiver，侧栏使用原生 List `onMove`。[gui-native-final-events.log](../performance/verification-20261101/gui-native-final-events.log) 记录了供应商两次、动作两次实际 payload/perform 和 source `end=1`；取消为 `end=0` 且未 perform。

本机测试方法为 `Cua.drag` 后在目标 padding 补一次 `click(duration: 500)` 以稳定释放。AX 前后顺序、实际 payload 和 session end 共同证明上述动作通过；**裸 `Cua.drag` 的释放与指针恢复可靠性仍未证实**，不将工具时序边界记录为正常物理鼠标失败或已验收的裸手势。Preview 使用隔离 fixture，退出后删除自身 suite，不能用它证明正式配置跨进程重启；保存与重新加载的依据来自逻辑和 App runtime。

| 当前实现的验收项 | 状态 / 最终证据 |
| --- | --- |
| 供应商左侧把手双向拖排、取消及卡片操作 | 通过；[下排](../performance/verification-20261101/provider-down.ax.txt)、[上排](../performance/verification-20261101/provider-up.ax.txt)、[取消](../performance/verification-20261101/provider-cancel.ax.txt) 与 [最终状态](../performance/verification-20261101/provider-final.ax.txt)；OpenAI 从第一移至第三再恢复，取消无改动，[展开](../performance/verification-20261101/provider-expanded.ax.txt) 仍对应 OpenAI |
| 动作双向拖排、快捷键与编辑对象保持 | 通过；[下排](../performance/verification-20261101/actions-down.ax.txt)、[上排](../performance/verification-20261101/actions-up.ax.txt) 与 [展开](../performance/verification-20261101/actions-expanded.ax.txt)；提问从第一移至第三再恢复，Prompt 与 `⌥A` 保留；不替代硬件快捷键触发测试 |
| 设置侧栏双向拖排、导航选择与保存 | GUI 通过；[下排](../performance/verification-20261101/sidebar-down.ax.txt)、[上排](../performance/verification-20261101/sidebar-up.ax.txt) 中 AI 模型往返重排，选择与详情仍正确；JSON 保存/重新加载由逻辑回归覆盖 |
| 图标库导入、跨供应商复用、应用与删除 | 通过；[导入](../performance/verification-20261101/provider-icon-import.ax.txt)、[复用](../performance/verification-20261101/provider-icon-reuse.ax.txt)、[应用](../performance/verification-20261101/provider-custom-icon-applied.ax.txt)、[清理](../performance/verification-20261101/provider-icon-test-cleanup.ax.txt)；只删除测试副本并恢复默认图标 |
| light/dark 图标在 Dock、侧栏、欢迎界面接入 | 素材与本机 Preview 显示已有记录；发布 ZIP 与已安装 2.2.0 的四项 light/dark 图标资源一致 |
| 主面板开/关、最小化与后台持续运行 | 由实际 WindowCoordinator/AppKit 生命周期 runtime 验证；不替代全部用户操作路径的专项 GUI 走查 |
| 透景材质与系统降低透明度偏好 | 本机 Preview 截图及透明窗口配置已有验证；Reduce Transparency 和 macOS 14/15 回退仍未完成专项实测 |
| 发布源码的完整 App runtime | 通过；[最终预检日志](../performance/verification-20261103/preflight-release.log) 覆盖排序、图标库、Dock、焦点、动画等待与 Escape |

## 兼容性与未验证范围

最低系统声明仍为 macOS 14，预编译发行包面向 Apple Silicon。macOS 14/15 真机毛玻璃回退未测；本机现代系统结果不能代替低版本兼容性。稳定自签名不等于 Apple Developer ID 或 notarization，首次手动安装继续遵循 [README](../../README.md) 的 quarantine 处理说明。

本轮没有完成四应用全场景的取词、硬件全局快捷键和写回验收，也没有重测真实模型质量；相关限制继续沿用 2.1.0 验收记录，先前有限 TextEdit/Word 样本不计为本轮全面通过。iCloud 配置同步的正式 entitlement、双机冲突处理与自定义图标缺失回退未做完整双设备验收，本地图标图片不随配置同步。

完整 VoiceOver、键盘读序、对比度、Reduce Transparency、120 Hz 帧预算及完整附件 UI 长期内存仍未完成专项实测。本轮没有新增可用于对外承诺的帧率、耗时或内存基线。
