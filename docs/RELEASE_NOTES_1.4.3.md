# SnapAI 1.4.3

SnapAI 1.4.3 是一次设置页 UI/UX 修复与打磨版本,重点解决置顶按钮状态不即时刷新、AI 路由区域留白过大的问题。

## 主要更新

- 修复设置窗口置顶按钮点击后图标不立即变化的问题。
- 新增 `SettingsWindowPinState`,让设置页按钮由可观察状态源驱动,点击后立即刷新图标、颜色、辅助功能状态和 hover 提示。
- 置顶状态变化仍会同步窗口层级、前置设置窗口、刷新主菜单和命令面板状态。
- 重新设计 AI 模型页顶部区域,把“当前使用”和“路由策略”合并为一张双列概览卡片。
- 顶部新增路由状态胶囊,自动路由 / 固定模型 / fallback 状态更容易扫读。
- 路由策略区域改为紧凑控制组,分段选择、自动路由和 fallback 开关共同填满右侧信息层级,不再留下大面积空白。
- 统一供应商卡片和动作卡片的横向展开行为,减少设置页中不同模块宽度不一致的观感。

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
