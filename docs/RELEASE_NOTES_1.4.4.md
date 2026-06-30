# SnapAI 1.4.4

SnapAI 1.4.4 是一次体验与稳定性优化版本,重点把已有 AI 路由能力从“后台诊断”提升为“用户可理解的透明状态”。

## 主要更新

- 结果面板新增路由解释摘要,展示本次将优先使用的供应商、模型和选择原因。
- 路由解释会同步展示自动路由偏好、fallback 状态、上下文包字符数、请求 token 估算、图片输入和预检跳过数量。
- 结果面板路由状态标题细分为固定模型、自动路由、自动路由 + Fallback 和无可用模型。
- AI 模型设置页新增路由预览,用户调整自动路由、fallback、当前模型或上下文包后,可以直接看到下一次请求的优先模型。
- 请求诊断新增 UI 友好的 `visibleRouteExplanation` 和 `visibleRouteStatusTitle`,完整诊断文本仍保留给复制诊断和排错。
- 为路由解释新增逻辑测试,覆盖自动路由、fallback、上下文、图片输入、token 估算和预检跳过。

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
