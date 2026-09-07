# SnapAI 2.0.0 重构验证报告

基线：`v1.6.75` / `7631ef4a6e83071cb1d6df3932c10dcf38873660`。本轮围绕请求完整性、存储可靠性、交互效率、模块边界与发布兼容性实施，保留现有数据格式和用户工作流。

## 核心变化

`SnapAILogic` 独占请求、设置、历史、隐私、路由和自动化类型。App 仅保留窗口、视图与系统交互适配。原有 symlink 以及自动化桥接中的同名类型删除，跨 target 内部 API 使用 Swift 5.9 的 `package` 访问级别。未引入第三方依赖。

请求拥有明确身份和配置快照；取消、替换及延迟投递均校验所属请求。流式 decoder 校验完成事件，渲染器只接收有效增量。SQLite 的 schema/FTS 迁移、写入及裁剪保持事务一致；设置迁移失败时不覆盖旧归档。密钥存储使用同目录原子替换，并协调多个 Store 的并发访问。

## 性能测量

环境：Apple M4，16 GB 内存，macOS 27。编译使用 `swiftc -O`。以下为本机合成场景，服务端推理速度和真实网络不在测量范围内。

### 历史存储

使用实际 `HistoryEntry` 和完整逻辑源，500 条记录，每条原文与结果各 2 KB，旧版与新版交替执行 5 轮，取中位数。收藏测试执行 50 次不同记录的更新。

| 场景 | 1.6.75 | 2.0.0 | 耗时降低 |
| --- | ---: | ---: | ---: |
| 500 条批量写入 | 144.990 ms | 36.849 ms | 74.6% |
| 30 次完整读取 | 400.870 ms | 131.495 ms | 67.2% |
| 50 次收藏更新 | 895.471 ms | 6.013 ms | 99.3% |

表格使用提交前完整代码的最后一轮复核。[最终原始样本](benchmarks/storage-2.0.0-final.json)；[首轮原始样本](benchmarks/storage-2.0.0.json)。两轮五次交替测量的中位数降幅分别为：批量写入 71.7% / 74.6%，读取 71.0% / 67.2%，收藏 98.0% / 99.3%。机器负载导致绝对耗时波动，未将这些结果推广为所有工作负载。复现：

```bash
scripts/benchmark-storage.sh 7631ef4
```

### 文本与呈现

同一优化构建 runner 对照旧版，统计中位数，并记录块数量/输出字节数累加值以避免空工作；内容正确性由独立逻辑回归验证。数值会随机器负载波动。[最终输出](benchmarks/streaming-2.0.0.txt)。

| 场景 | 1.6.75 | 2.0.0 |
| --- | ---: | ---: |
| 400 段纯文本 Markdown | 3.768 ms | 1.129 ms |
| 200 节混合 Markdown | 6.646 ms | 4.592 ms |
| 6000 组 think spans | 25.792 ms | 5.145 ms |

```bash
scripts/benchmark-streaming.sh 7631ef4
```

调度回归另外验证：502 次 Markdown 刷新执行 2 次解析并只发布最新结果；没有可见 token 时打字机 timer 不运行。这里测量的是本地处理和调度，不声称远程模型响应速度同比提升。

## 可靠性验证范围

- 协议：多行 SSE、UTF-8/CRLF、空响应、错误事件、限额、提前 EOF、所有 think tag 切分位置与 Markdown 围栏。
- 请求：立即取消、同 client 重启、释放 client、VM 新请求隔离、停止/失败不保存不写回、无路由、关闭历史、只有思考而无正文。
- 存储：旧 SQLite/FTS 迁移、失败事务回滚、文件替换/删除、权限错误恢复、并发首次建库和写入、损坏配置保留、设置重试、过期查询。
- 密钥：30 次并发写入全部可恢复，临时写失败不损坏旧文件，master key 缺失与恢复。
- 同步：失败保留待同步标记，启动续传。
- 窗口：关闭/重开动画竞态、关闭内容释放、按窗口处理 Escape、详情优先关闭和输入法保护。
- UI：真实 AppKit/SwiftUI 窗口检查设置、结果、快速输入、历史、命令面板和引导，覆盖浅深色、键盘操作和缩放。

SQLite 并发与恢复用例连续执行 15 轮。所有数据相关测试使用独立 UserDefaults、临时历史、临时密钥与临时路由指标；网络测试使用本地 fixture 拦截。

## 发布验证入口

```bash
scripts/run-logic-tests.sh
scripts/run-streaming-runtime-tests.sh
scripts/run-app-runtime-tests.sh
scripts/run-macos-smoke-tests.sh --skip-logic
scripts/preflight-release.sh --require-clean --require-synced
```

发布门禁验证 SwiftPM 构建、模块边界、供应链、回归、App 启动、稳定代码签名、ZIP 结构、SHA256、已签名 bundle 内的公钥与 manifest 签名、SBOM，以及主程序和 updater 的 `LC_BUILD_VERSION.minos = 14.0`。Debug 构建和源/包内公钥不一致的负例均验证为拒绝打包。启动 smoke 使用独立数据，等待真实 AppDelegate 的就绪标记再检查存活和正常退出，不注册生产快捷键或触发同步。

1.6.75 的公开发布包实测 `minos = 27.0`。2.0.0 使用 `Package.swift` 的 macOS 14 平台声明生成实际发布二进制，避免构建机器的系统版本意外成为最低要求。兼容性验证包含 deployment target 和 macOS CI；没有把它等同于在每个历史 macOS 小版本上完成手工测试。


## 界面验收记录

全部截图来自使用演示数据的独立预览应用。检查了设置全部分区、差异预览、权限健康、历史列表/阅读联动、快捷输入的中文多行文本、命令面板中文搜索/方向键/回车，以及浅深色和紧凑窗口。权限复查不会自动弹出授权请求。

- [设置（浅色）](screenshots/snapai-settings-light.png) / [设置（深色、紧凑）](screenshots/snapai-settings-dark.png)
- [结果（浅色）](screenshots/snapai-result-light.png) / [结果（深色）](screenshots/snapai-result-dark.png) / [紧凑结果](screenshots/snapai-result-compact.png)
- [快捷输入](screenshots/snapai-quick-dark.png) / [紧凑输入](screenshots/snapai-quick-compact.png)
- [历史记录](screenshots/snapai-history-light.png) / [动作编辑](screenshots/snapai-actions-light.png)
- [差异预览](screenshots/snapai-diff-light.png) / [权限健康](screenshots/snapai-health-light.png)
- [首次引导](screenshots/snapai-welcome-light.png) / [命令面板](screenshots/snapai-commands-light.png)

```bash
scripts/run-ui-preview.sh result light --compact
```

预览 bundle 即使不带参数打开，也只进入独立演示环境；配置使用临时专用 suite，历史、密钥和路由指标隔离。生产 Release 不包含预览入口。
