# SnapAI 1.4.1

SnapAI 1.4.1 是一次 UI/UX 收尾优化版本,重点让高频窗口更紧凑、更稳定、更容易扫读。功能内核延续 1.4.0 的本地模型隐私优先、云端 fallback 确认、写回兼容矩阵和权限诊断能力,本版主要提升日常使用手感。

## 主要更新

- 新增统一的轻量界面样式层,统一紧凑卡片、状态胶囊和图标按钮。
- 设置页窗口收敛为 640x500,外层内容容器更轻,减少“卡片套卡片”的厚重感。
- 设置页供应商、动作、历史统计和工作模式区域使用更一致的紧凑视觉样式。
- 结果面板新增显式追问发送按钮,追问输入和结果操作分行展示,降低底部工具条挤压。
- 结果面板顶部新增当前模型与路由状态条,生成中和 fallback 状态更容易被看见。
- 历史窗口筛选栏拆成两行,搜索、筛选和操作按钮不再互相挤压。
- 历史窗口筛选状态改为胶囊摘要,当前筛选条件更容易扫读。
- 权限健康中心改为自适应状态卡片,窄宽度下不再依赖容易变形的三列 Grid 行。
- 权限健康中心的最近请求和签名信息支持多行展示,复制诊断入口保持在顶部。

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

