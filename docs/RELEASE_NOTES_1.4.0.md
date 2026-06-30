# SnapAI 1.4.0

SnapAI 1.4.0 聚焦隐私模式、本地模型、写回诊断和失败可观察性。本版继续强化 SnapAI 作为 macOS 跨应用 AI 操作层的可靠性:用户可以更清楚地知道请求会走本地还是云端,写回失败时能看到更具体的恢复建议,权限健康中心也能汇总最近一次 AI 请求状态。

## 主要更新

- 新增 LM Studio 本地供应商预设,默认使用 `http://localhost:1234/v1`。
- 增强本地端点识别,覆盖 `localhost`、`127.0.0.1` 和 `::1`。
- 隐私模式下自动路由优先使用本地模型,并把云端候选明确标记为备用模型。
- 本地模型失败后,如果下一个候选是云端模型,不会静默自动 fallback;诊断会提示需要用户确认或手动切换。
- 新增本地模型健康诊断,针对 Ollama、LM Studio 和通用本地 OpenAI 兼容服务给出 API Key、模型加载和 Base URL 恢复建议。
- 新增写回兼容性矩阵,首批覆盖 Safari、Chrome、Edge、微信、飞书、Obsidian、Notion、Xcode 和 Word。
- 写回失败或降级为复制时,诊断建议会结合目标应用给出更具体的恢复路径。
- 请求诊断新增动作 pipeline 信息,展示输入、隐私、输出和模型策略。
- 权限健康中心新增最近 AI 请求状态,完整和精简诊断都会包含失败摘要与恢复建议。
- README 和 UI 总览图已更新为 1.4.0。

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

## 本地模型说明

Ollama 和 LM Studio 这类本地 OpenAI 兼容服务通常仍需要在 SnapAI 中填写一个非空 API Key 占位符:

- Ollama 可填写 `ollama`
- LM Studio 可填写 `lm-studio`
- 其他本地兼容服务可填写 `local`

隐私模式本地优先不会阻止你手动选择云端模型;它只会避免在本地失败后静默切到云端。

## 校验

本次发布前执行:

- `git diff --check`
- `scripts/run-logic-tests.sh`
- `swift build`
- `scripts/preflight-release.sh`

