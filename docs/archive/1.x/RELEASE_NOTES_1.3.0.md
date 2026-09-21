# SnapAI 1.3.0

SnapAI 1.3.0 是一次阶段性收尾版本,重点从“可用的菜单栏 AI 工具”推进到“更完整的 macOS AI 工作台”。本版围绕快捷键、命令面板、历史知识库、隐私保护、权限诊断、写回事务和应用内更新做了系统性打磨。

## 主要更新

- 新增 `Command + K` 命令面板,可搜索动作、模型、上下文包、历史记录、设置项和常用系统行为。
- 补齐动作与结果面板快捷键体系,让复制、替换、追加、继续追问、重新生成等行为更适合键盘操作。
- 历史记录升级为独立窗口,支持搜索、收藏、删除单条、按动作/模型/隐私标签筛选,并可从历史创建上下文包。
- 增强 AI 路由能力,可按动作、文本长度、图片输入、速度/质量偏好选择模型,并在失败时 fallback 到可用候选。
- 增强隐私保护,支持发送前预览、本地脱敏规则、高风险内容强制确认、历史仅元信息模式和导出保护。
- 完善权限健康中心,集中展示辅助功能、屏幕录制、开机启动、签名、热键注册和安装诊断。
- 优化替换/追加事务,保护用户剪贴板,失败时提供可复制诊断和恢复建议。
- 强化更新链路,应用内检查 GitHub Release,下载后校验 bundle id、版本、签名、SHA256,并尝试替换后自动重启。
- README 补充安装、`xattr -cr`、签名、Keychain、URL Scheme、自动化和发布校验说明。

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
- `./build.sh`
- `codesign --verify --deep --strict --verbose=2 SnapAI.app`
- `scripts/preflight-release.sh`

