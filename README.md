# SnapAI

SnapAI 是一个 macOS 菜单栏 AI 工具。你可以在任意应用里选中文字,一键提问、翻译、润色、总结或解释代码;也可以直接打开快捷提问面板输入问题。

![SnapAI 设置界面](docs/snapai-settings.png)

## 快速安装

系统要求:macOS 14 或更高版本。

1. 打开 [GitHub Releases](https://github.com/junchan0412/SnapAI/releases),下载最新的 `SnapAI-vX.X.X.zip`。
2. 解压后,把 `SnapAI.app` 移动到 `/Applications` 或 `~/Applications`。建议先移动到固定位置,再授权辅助功能权限。
3. 如果 macOS 提示“已损坏”“无法打开”或“来自未认证开发者”,在终端执行:

```bash
xattr -cr /Applications/SnapAI.app
open /Applications/SnapAI.app
```

如果你放在用户应用目录:

```bash
xattr -cr ~/Applications/SnapAI.app
open ~/Applications/SnapAI.app
```

4. 首次启动后,到系统设置授予辅助功能权限:

```text
系统设置 -> 隐私与安全性 -> 辅助功能 -> 勾选 SnapAI
```

5. 点击菜单栏里的 SnapAI 图标,进入设置页填写 AI 供应商、API Key 和模型。

## 为什么需要 `xattr -cr`

当前 SnapAI 没有使用 Apple Developer ID 公证发布。通过浏览器从 GitHub 下载后,macOS 会给压缩包或应用添加 quarantine 隔离属性。未公证应用在隔离状态下可能会被 Gatekeeper 拦截,表现为无法打开、提示损坏,或需要额外确认。

`xattr -cr /Applications/SnapAI.app` 会递归清除应用 bundle 上的扩展属性,包括 quarantine。应用第一次启动前还没有机会自己处理这个属性,所以首次手动安装时需要用户执行一次。

这一步不会替代辅助功能授权。SnapAI 读取选中文字、模拟复制和粘贴仍然需要你在系统设置中授予辅助功能权限。

## 使用方式

默认快捷键:

| 功能 | 快捷键 |
|------|--------|
| 提问选中文字 | `Option + A` |
| 翻译选中文字 | `Option + T` |
| 快捷提问面板 | `Option + Space` |

基本流程:

1. 在任意应用中选中文字。
2. 按 `Option + A` 提问,或按 `Option + T` 翻译。
3. 在浮动结果窗中复制结果、替换原文、追加到文档,或继续追问。
4. 不想先选中文字时,按 `Option + Space` 打开快捷提问面板。

所有动作、快捷键、Prompt、模型和供应商都可以在设置里自定义。

## 功能概览

- 自定义动作:内置提问、翻译、润色、总结、解释代码,也可新增动作。
- 全局快捷键:每个动作都能设置独立快捷键,设置页会阻止冲突快捷键保存。
- 快捷提问面板:无需选中文字,直接输入问题,也支持粘贴图片或截图。
- 取词策略:优先使用 Accessibility API 读取选中文本,失败后才模拟 `Command + C`。
- 多供应商与多模型:支持 OpenAI 兼容协议和 Anthropic 原生协议。
- Keychain 存储:API Key 存入 macOS Keychain,导出配置不会包含密钥。
- Markdown 渲染:支持标题、列表、引用、代码块、加粗、链接等基础格式。
- 替换原文:可把生成结果粘贴回原选区,适合翻译和润色。
- 历史记录:保存最近结果,支持回看、复制和重新发起。
- 历史知识库:历史窗口支持搜索、收藏、删除、按动作/模型/标签筛选,并可为单条记录添加标签。
- 上下文包:可保存项目背景、术语表、写作风格或代码栈偏好,并自动合并进请求上下文。
- 工作流模板:可一键创建邮件回复、会议纪要、代码审查、中英双语润色、图片理解等动作。
- 替换前预览:替换原文前显示原文/新文 Diff,确认后才写回目标应用。
- 文本事务保护:替换和追加会保护用户剪贴板,并尽量恢复触发前的焦点应用。
- 隐私规则测试:脱敏规则可在设置中实时预览替换结果。
- iCloud 配置同步:可同步供应商结构、动作和快捷键,不包含 API Key 和历史内容。
- 应用内更新:检查 GitHub Release,下载新版 zip,原地替换应用并重启。
- 开机自启:可在设置中开启,基于 `SMAppService`。

## AI 配置示例

| 服务 | 协议 | Base URL | 模型名 |
|------|------|----------|--------|
| OpenAI | OpenAI 兼容 | `https://api.openai.com/v1` | `gpt-4o-mini` |
| DeepSeek | OpenAI 兼容 | `https://api.deepseek.com/v1` | `deepseek-chat` |
| Ollama 本地 | OpenAI 兼容 | `http://localhost:11434/v1` | `llama3.1` |
| Claude | Anthropic 原生 | `https://api.anthropic.com/v1` | `claude-sonnet-4-6` |

安全限制:

- 非本机 HTTP 端点会被拒绝,避免 API Key 通过明文网络发送。
- 本机 HTTP 仅用于 `localhost`、`127.0.0.1`、`::1`,主要服务 Ollama 等本地模型。

## 更新机制

SnapAI 的菜单里有“检查更新”。发现新版本后,你可以选择“安装并重启”。

当前实现会:

1. 在应用内通过 macOS 网络栈请求 GitHub Releases 最新版本,不依赖终端、`gh` 或 `curl`。
2. 优先使用 GitHub API；如果 API 返回 403 或临时不可用,会回退到 GitHub 普通 Release 页面获取最新版本标签。
3. 找到或构造 Release 里的 SnapAI zip 资产下载地址。
4. 下载到临时目录并解压。
5. 校验解压出的 `SnapAI.app` bundle id 与当前应用一致。
6. 使用 `codesign --verify --deep --strict` 做基础签名校验。
7. 用脱离当前应用生命周期的临时安装脚本等待当前 SnapAI 进程退出。
8. 在原安装路径替换应用。
9. 对替换后的应用执行:

```bash
xattr -cr "$APP_PATH"
```

10. 使用 `open -n -F` 自动重新打开 SnapAI；如果首次打开失败,会重试并把过程写入临时安装日志。

因此,应用已经正常启动以后,后续应用内更新会尽量自动处理 quarantine。首次从 GitHub 下载时,因为应用尚未运行,仍需要用户手动执行 `xattr -cr`。

如果自动更新提示安装位置不可写,请把 `SnapAI.app` 移动到 `~/Applications` 后再试。应用内更新需要能够写入当前安装目录。

## 辅助功能权限与签名

macOS 的辅助功能权限和应用的代码身份有关。SnapAI 当前没有 Apple Developer ID,所以发布包不是 Apple 公证应用。

当前仓库提供两种构建签名方式:

- 有稳定签名身份时:`build.sh` 会使用 `CODESIGN_IDENTITY` 或 `SnapAI Local Signing`。
- 没有稳定签名身份时:`build.sh` 会回退到 ad-hoc 签名。

ad-hoc 签名每次构建都可能让代码身份变化,更新后更容易被系统要求重新授予辅助功能权限。为了减少这种情况,可以创建本机自签名代码签名证书:

```bash
./scripts/create-local-signing-identity.sh
./build.sh
```

注意:

- 自签名不等同于 Apple Developer ID 或 notarization。
- 首次从旧 ad-hoc 版本切换到自签名版本时,macOS 可能仍会要求重新授予一次辅助功能权限。
- 后续只要继续使用同一个证书构建,代码身份会更稳定,可减少重复授权。
- 对其他用户的机器来说,自签名证书默认不受系统信任,所以首次 GitHub 下载仍可能需要 `xattr -cr`。

## 构建

本项目是 SwiftPM 结构,但当前构建脚本直接用 `swiftc` 编译并组装 `.app`:

```bash
./build.sh
```

构建成功后会生成:

```text
SnapAI.app
```

如果你要打包 Release:

```bash
./build.sh
scripts/package-release.sh
```

`scripts/package-release.sh` 会生成干净的 zip 和 `snapai-manifest-vX.X.X.json`,并写入 zip 的 SHA256。若设置 `SNAPAI_MANIFEST_PRIVATE_KEY`,脚本还会额外生成 manifest 签名文件。

## 常见问题

### 双击提示应用损坏怎么办

先确认已经把应用移动到固定位置,然后执行:

```bash
xattr -cr /Applications/SnapAI.app
open /Applications/SnapAI.app
```

### 快捷键没有反应怎么办

检查三件事:

1. 系统设置里是否给 SnapAI 授予了辅助功能权限。
2. 设置页里动作是否启用,快捷键是否冲突。
3. 当前应用中是否真的选中了可复制的文本。

### 为什么替换原文失败

替换原文依赖辅助功能权限和模拟粘贴。请确认:

- SnapAI 有辅助功能权限。
- 目标应用允许粘贴。
- 触发动作后不要立即切换到其他输入位置。

### API Key 会不会导出或同步

不会。API Key 存在 macOS Keychain 中。配置导出和 iCloud 配置同步都不包含 API Key。

### iCloud 会同步历史记录吗

不会。iCloud 只同步配置结构,例如供应商、动作、快捷键、系统 Prompt 等;不会同步历史记录、统计、窗口尺寸或 API Key。

## 项目结构

```text
Sources/SnapAI/
  main.swift            应用入口
  AppDelegate.swift     菜单栏、主菜单、快捷键、取词到结果窗流程
  Settings.swift        设置模型与 UserDefaults 持久化
  Provider.swift        AI 供应商与模型配置
  Action.swift          自定义动作与翻译目标语言
  AIClient.swift        OpenAI / Anthropic 流式请求
  TextCapture.swift     Accessibility 取词与复制兜底
  ResultViewModel.swift 结果窗状态机
  ResultView.swift      结果窗 UI
  TextEditTransaction.swift 替换/追加事务与剪贴板保护
  TextDiff.swift        替换前 Diff 计算
  DiffPreviewWindow.swift 替换前预览窗口
  MarkdownView.swift    轻量 Markdown 渲染
  FloatingPanel.swift   浮动面板
  QuickInput.swift      快捷提问面板
  SettingsView.swift    设置界面
  ContextProfile.swift  上下文包
  ModelCapability.swift 模型能力推断与路由依据
  HotKeyManager.swift   Carbon 全局快捷键注册
  HotKeyRecorder.swift  快捷键录制控件
  Keychain.swift        API Key 存储
  iCloudSync.swift      iCloud 配置同步
  UpdateChecker.swift   GitHub Release 检查与应用内更新
  LoginItem.swift       开机自启
  OnboardingView.swift  首次启动引导
Resources/
  Info.plist
  AppIconLight.icns
  AppIconDark.icns
scripts/
  create-local-signing-identity.sh
build.sh
```
