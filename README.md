# SnapAI

在 **任意应用** 中选中文字,一键用 AI 提问或翻译。原生 SwiftUI + AppKit,菜单栏常驻,低开销。

![SnapAI 设置界面](docs/snapai-settings.png)

## 功能

- **自定义动作**:内置提问、翻译、润色、总结、解释代码,也可新增动作并配置 Prompt、图标、快捷键和替换行为
- **全局快捷键**:选中文字后按 `⌥A` 提问、`⌥T` 翻译,也可为任意动作单独设置快捷键
- **快捷提问面板**:按 `⌥Space` 直接输入问题,不依赖预先选中文字
- **划词无感取词**:优先用 Accessibility API 直读选中文本,失败自动回退模拟 `⌘C`
- **多供应商 / 多模型**:可保存多个供应商(各自的协议 / 端点 / Key / 模型列表),供应商与模型都能逐个启用 / 关闭;菜单栏 ✨ → 切换模型 一键切换当前使用的「供应商 + 模型」
- **Keychain 存储**:API Key 存入 macOS Keychain,配置导出不会包含密钥
- **自定义模型**:支持 OpenAI 兼容协议(OpenAI / DeepSeek / Ollama / 中转站等)与 Anthropic 原生协议
- **极简配置**:只需填端点地址(如 `api.openai.com`),应用自动补全 `/v1` 等路径;填好地址和 Key 后可一键拉取模型列表下拉选择,无需手动输入模型名
- **连接测试**:可对单个供应商发起轻量测试,快速确认端点、Key 与模型是否可用
- **Dock 图标 + 主菜单**:Dock 显示图标,点击可打开设置;顶部菜单栏含 App / 编辑 / 窗口 菜单(可在「通用」里关闭 Dock 图标,仅留菜单栏)
- **Markdown 渲染**:结果按 Markdown 渲染(标题/列表/引用/代码块/加粗等),代码块可一键复制
- **替换原文**:可将生成结果写回原选区,适合翻译和润色工作流
- **历史记录**:保留最近结果,可从菜单或设置页回看、复制、重新发起
- **配置导入/导出**:迁移供应商、动作、快捷键等配置;历史记录和 API Key 不会导出
- **首次引导**:新用户首次启动会看到权限、配置与使用步骤
- **打字机动画**:流式结果逐字揭示,带闪烁光标,速度可调(关闭/慢/标准/快)
- **可调整浮窗**:结果浮窗可调整大小并记忆尺寸;右上角图钉固定后点击外部不自动关闭(`Esc` 可解除固定)
- **开机自启**:设置「通用」里可开启(基于 SMAppService)
- **检查更新**:菜单栏 ✨ → 检查更新,会跳转到最新 GitHub Release 下载页
- **标准编辑快捷键**:所有输入框支持 `⌘C / ⌘V / ⌘X / ⌘A / ⌘Z`
- **菜单栏常驻**:无 Dock 图标(LSUIElement),不打扰

## 下载

前往 [GitHub Releases](https://github.com/junchan0412/SnapAI/releases) 下载最新 `SnapAI.zip`,解压后将 `SnapAI.app` 移动到 `/Applications` 或 `~/Applications`。

## 构建

```bash
./build.sh
```

生成 `SnapAI.app`。

> **开机自启注意**:`SMAppService` 通过固定路径注册登录项。若要使用开机自启,
> 请先把 `SnapAI.app` 移动到稳定位置(如 `/Applications` 或 `~/Applications`),
> 再在设置里开启,不要停留在反复 rebuild 的目录里。

> 本机仅装了 Command Line Tools,其 SwiftPM(`swift build`)有缺陷,故 `build.sh`
> 直接用 `swiftc` 编译。若以后装了完整 Xcode,也可用 `Package.swift` 打开。

## 首次使用

1. `open SnapAI.app`
2. 授予 **辅助功能** 权限:系统设置 → 隐私与安全性 → 辅助功能 → 勾选 SnapAI
   (用于读取选中文字 / 模拟复制按键)
3. 点击菜单栏 ✨ → 设置,填入 API Key、模型名,选择协议
4. 在任意应用选中文字,按 `⌥A` / `⌥T`;或按 `⌥Space` 打开快捷提问面板
5. 后续可通过菜单栏 ✨ → 检查更新 前往最新 Release

## 配置示例

| 服务 | 协议 | Base URL | 模型名 |
|------|------|----------|--------|
| OpenAI | OpenAI 兼容 | `https://api.openai.com/v1` | `gpt-4o-mini` |
| DeepSeek | OpenAI 兼容 | `https://api.deepseek.com/v1` | `deepseek-chat` |
| Ollama(本地) | OpenAI 兼容 | `http://localhost:11434/v1` | `llama3.1` |
| Claude | Anthropic 原生 | `https://api.anthropic.com/v1` | `claude-sonnet-4-6` |

## 项目结构

```
Sources/SnapAI/
  main.swift            入口
  AppDelegate.swift     菜单栏、快捷键注册、取词→展示串联
  Settings.swift        设置模型 + UserDefaults 持久化
  HotKeyManager.swift   Carbon 全局快捷键
  TextCapture.swift     AX 直读 + 模拟复制兜底
  AIClient.swift        OpenAI / Anthropic 流式 SSE
  Action.swift          自定义动作与翻译目标语言
  History.swift         历史记录模型
  ResultViewModel.swift 浮动窗状态机 + 打字机动画
  ResultView.swift      浮动窗 SwiftUI + 闪烁光标
  MarkdownView.swift    轻量 Markdown 渲染器
  FloatingPanel.swift   NSPanel 浮动窗 + 定位/失焦关闭
  SettingsView.swift    设置界面
  QuickInput.swift      快捷提问面板
  OnboardingView.swift  首次启动引导
  Keychain.swift        API Key 安全存储
  UpdateChecker.swift   GitHub Release 更新检查
  HotKeyRecorder.swift  快捷键录制控件
  LoginItem.swift       开机自启 (SMAppService)
Resources/Info.plist
docs/snapai-settings.png
build.sh
```
