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
5. **验收**:运行后 SnapAI 打开并提交处理,快捷指令结果是一段可读文本
   (如 `已提交 SnapAI 处理:…`);把文本参数接到「剪贴板」动作即构成
   「总结剪贴板」这类自动化。

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
- Intent 层**只做参数装配**,命令语义仍唯一归属 `AutomationURLCommand`;
  `testAutomationIntentsCoverCoreShortcutsPaths` 断言三条路径能无损映射回 URL 命令。
- 覆盖范围:目前 3 条核心路径。其余 URL 命令继续用 `snapai://` 深链,例如
  `open location "snapai://run?action=总结"`;扩展 Intent 时保持同样的
  「装配 + 转交 runAutomationCommand」写法即可。
