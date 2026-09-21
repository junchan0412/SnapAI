# SnapAI 1.4.2

SnapAI 1.4.2 是一个聚焦设置窗口体验的修复版本。它修正了置顶按钮状态显示与 AI 路由卡片布局问题,让设置页在日常配置时更直观、更稳定。

## 主要更新

- 修复设置窗口右上角置顶按钮的图标语义:未置顶显示空心图钉,已置顶显示实心图钉。
- 命令面板和菜单继续使用动作语义:未置顶时显示“置顶设置窗口”,已置顶时显示“取消置顶设置窗口”。
- 点击置顶状态后会立即更新窗口层级,并把设置窗口前置显示。
- 置顶状态变化后会刷新主菜单,避免菜单或命令面板展示旧状态。
- 为置顶按钮增加明确的辅助功能状态值:未置顶 / 已置顶。
- 修复 AI 路由卡片未铺满设置页宽度的问题。
- 统一“当前使用”和“AI 路由”卡片的横向展开行为,减少右侧空白和视觉断裂。

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
