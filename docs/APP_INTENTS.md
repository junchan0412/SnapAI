# 在「快捷指令」里使用 SnapAI(App Intents 运行手册)

面向使用者:本文回答「为什么 Shortcuts 里看不到 SnapAI、要做什么才能列出并执行」。
面向维护者:本文也记录元数据是怎么进包的,以及改动后如何复验。

## 我已经修掉的(代码侧)

SwiftPM 构建**不会**执行 Xcode 的 App Intents 元数据提取阶段,所以此前
`SnapAI.app` 里根本没有元数据,Shortcuts 自然列不出来 —— 与你机器设置无关。

`build.sh` 现在会显式调用工具链里的 `appintentsmetadataprocessor`,把结果写进
`SnapAI.app/Contents/Resources/Metadata.appintents/`(与 Yoink、SurfED 等
第三方应用同一位置),并校验 `version.json` 存在,缺失即构建失败:

```bash
./build.sh --release
ls SnapAI.app/Contents/Resources/Metadata.appintents   # version.json + extract.actionsdata
```

当前导出的三个 Intent:`SnapAIRunActionIntent`、`SnapAIOpenQuickInputIntent`、
`SnapAISwitchModelIntent`(元数据里 `isDiscoverable: true`)。

## 你需要做的(按顺序)

1. **装到 /Applications**。Shortcuts 只索引已安装的应用;从 zip 解压到
   下载目录或桌面不会出现。覆盖安装后重启「快捷指令」。
2. **至少启动一次**。启动会向 LaunchServices 注册应用;若仍看不到,手动注册:
   ```bash
   /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/SnapAI.app
   ```
3. **打开「快捷指令」→ 新建快捷指令 → 搜索动作**。可搜「SnapAI」,或直接搜动作名:
   - `用 SnapAI 处理文本` —— 参数「文本」**留空即读剪贴板**,「动作」留空用第一个启用动作;
   - `打开 SnapAI 快捷提问` —— 可预填文本;
   - `切换 SnapAI 模型` —— 按供应商 + 模型名。
   也可以用顶部的「App 快捷指令」(AppShortcutsProvider 提供的即时短语)。
4. **首次运行会弹授权**:允许 SnapAI 打开、允许读取剪贴板。Intent 标了
   `openAppWhenRun`,所以 SnapAI 会先被拉起再执行。
5. **验收**:运行后等待 AI 生成结束，快捷指令结果默认就是完整 AI 正文；
   把结果接到「拷贝到剪贴板」「存储文件」或「发送邮件」动作即可继续处理。
   例如「获取剪贴板 → 用 SnapAI 处理文本（动作：总结）→ 快速查看」。

## 返回正文、错误和等待时间

「用 SnapAI 处理文本」展开参数后提供「返回格式」和「等待秒数」：

- **AI 正文（默认）**：成功返回完整正文；失败抛出带稳定错误码的错误，快捷指令停止，
  不会把「已提交」或生成中断的部分正文当作成功结果。
- **JSON（含错误信息）**：成功和失败都返回 JSON 文本。下一步接「从输入中获取词典」，
  判断 `status`，成功读取 `text`，失败读取 `error.code` / `error.message`。
- **等待秒数**：默认 120 秒，限制为 1–600 秒；从发送前隐私确认完成后开始计时，
  包含后续允许的 fallback 请求。超时会取消网络请求，不等待打字机动画。

成功示例：

```json
{"status":"succeeded","text":"这里是 AI 正文"}
```

失败示例：

```json
{"status":"failed","text":"","error":{"code":"timed_out","message":"SnapAI 处理超时，请重试或增加等待时间。"}}
```

| `error.code` | 含义 / 处理 |
| --- | --- |
| `empty_input` | 文本和剪贴板都为空，传入文本后重试 |
| `app_unavailable` | 应用尚未就绪，稍后重试 |
| `action_unavailable` | 没有启用的动作，或指定动作不存在；检查名称 |
| `privacy_cancelled` | 用户取消了发送前确认，未发出请求 |
| `cancelled` | 运行任务已取消，不返回部分正文作为成功 |
| `timed_out` | 等待超时，可增加等待秒数或更换模型 |
| `request_failed` | 路由不可用、HTTP / SSE 错误或响应不完整，查看安全处理后的 message |
| `empty_response` | 生成结束但没有正文 |

正文模式的错误还提供 NSError domain `com.snapai.automation` 和 `userInfo["code"]`。
手动停止整条快捷指令时，系统可能同时停止下游步骤；需要继续按错误码分支的流程，
应使用 JSON 模式和等待超时。

Shortcuts 使用与结果面板相同的脱敏、发送前预览、高风险确认、路由和历史保存策略。
高风险内容仍需在 SnapAI 中确认；取消确认会返回 `privacy_cancelled`。
本地优先模式下，本地模型失败后不会静默把内容发往云端。
每次自动化独立执行，不替换当前结果面板中的会话，也不自动写回前台应用。

## 列不出来时按这个顺序排

| 现象 | 处理 |
| --- | --- |
| 搜索 SnapAI 无结果 | 应用不在 `/Applications`,或没启动过 → 第 1、2 步 |
| 装了新版本仍显示旧动作 | 元数据没更新 → 重新 `./build.sh` 并覆盖安装;`killall Shortcuts` 后重开 |
| 有动作但运行报「SnapAI 未在运行」 | 需要应用可被系统拉起;确认 `/Applications/SnapAI.app` 是最终安装位置 |
| 剪贴板读不到 | 首次运行时拒绝过授权 → 系统设置 → 隐私与安全性 → 快捷指令/自动化 里放行 |

## 维护者须知

- 改动 `SnapAIIntents.swift` 后必须重新构建,元数据才会更新(它由源码 +
  `.swiftconstvalues` 提取,不随二进制自动携带)。
- 门禁锁定:`appintentsmetadataprocessor` 出现在 `build.sh`、
  `Metadata.appintents/version.json` 生成校验、`SnapAIRunActionIntent` 存在。
- Intent 层负责参数装配和结果格式；文本处理交给 `runAutomationAction`，
  由 `AutomationActionExecution` 等待独立 `ResultViewModel` 的生成结束。
  `SubmissionPipeline` 负责脱敏与确认，路由、fallback、历史继续复用结果面板的实现。
  `testAutomationIntentsCoverCoreShortcutsPaths` 保留三条路径的 URL 参数映射检查。
- `Tests/Runtime/AutomationActionRuntimeTests.swift` 使用本地 URLProtocol fixture 检查真实流完成、
  慢打字机时直接返回完整正文、HTTP/空响应错误、超时、请求前和请求中取消、隐私拒绝、
  脱敏后的实际请求体、本地优先阻止静默云 fallback，以及 JSON / NSError 错误码。
  运行 `scripts/run-app-runtime-tests.sh`；测试不调用真实供应商。
- 覆盖范围:目前 3 条核心路径。其余 URL 命令继续用 `snapai://` 深链,例如
  `open location "snapai://run?action=总结"`。URL 深链继续打开结果面板；需要组合返回值时使用 Intent。
- release 包的元数据提取、覆盖安装后发现动作、真实 Shortcuts 串联仍需单独验收；
  fixture 通过不代表已经完成系统索引和授权链路的实机验收。
