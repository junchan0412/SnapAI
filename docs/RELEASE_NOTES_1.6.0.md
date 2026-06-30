# SnapAI 1.6.0

SnapAI 1.6.0 是一次主链路稳定性和代码质量优化版本,重点打磨“任意应用选中文字 -> SnapAI 理解上下文 -> 执行动作 -> 安全写回”的完整体验。

## 主要更新

- 文本捕获新增结构化结果,可区分 Accessibility 直读、剪贴板兜底、剪贴板保护、复制超时和空内容。
- 权限健康中心和请求诊断新增捕获方式、失败原因、剪贴板保护原因和等待次数,便于排查不同应用里的取词问题。
- 新增选区来源上下文,会把前台应用归类为浏览器、代码编辑器、终端、文档编辑器、聊天工具、邮件客户端或 PDF/文档阅读器。
- AI 请求会收到粗粒度来源类型和上下文提示,帮助模型按代码、日志、网页、邮件或聊天片段等语境理解选中文字。
- 来源上下文不会把窗口标题、文件路径或具体应用名发送给 AI;诊断里的应用名也会经过敏感信息清洗。
- 请求 pipeline 诊断新增捕获路径和来源类型,与上下文包、隐私预览、自动路由和 fallback 状态一起形成完整请求说明。
- 保留 1.5.0 的项目记忆、历史知识库、命令面板主入口和动作模板库。
- 更新 README 和 UI 总览图到 1.6.0,补充选中文字主链路使用说明。

## 安装提示

SnapAI 当前没有 Apple Developer ID 公证。首次从 GitHub 下载后,如果 macOS 提示应用损坏或无法打开,请先移动到固定位置,再执行:

```bash
xattr -cr /Applications/SnapAI.app
open /Applications/SnapAI.app
```

如果放在用户应用目录:

```bash
xattr -cr ~/Applications/SnapAI.app
open ~/Applications/SnapAI.app
```

应用内更新会尽量自动清理 quarantine,但首次手动下载仍需要这一步。

## 校验

本次发布前执行:

- `git diff --check`
- `scripts/run-logic-tests.sh`
- `swift build`
- `scripts/preflight-release.sh`
