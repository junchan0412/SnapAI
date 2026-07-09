# SnapAI 1.6.17

SnapAI 1.6.17 继续处理审计报告中 `SnapAILogic` target 边界脆弱的问题。本版在已有 symlink manifest 的基础上,增加 UI-only 文件和 UI 渲染类 import 的拒绝规则。

## 改进

- `scripts/check-logic-symlinks.sh` 新增禁止文件名规则,阻止设置页 section、窗口、面板、View、AppDelegate、QuickInput 等 UI-only 文件进入 `SnapAILogic`。
- 新增禁止 import 规则,拒绝 `SwiftUI`、`UniformTypeIdentifiers`、`WebKit`、`PDFKit`、`Quartz` 等 UI/文档渲染依赖进入逻辑 target。
- 该检查已经被 CI、`scripts/run-macos-smoke-tests.sh` 和 release preflight 复用。

## 发布资产

- `SnapAI-v1.6.17.zip`
- `snapai-manifest-v1.6.17.json`
- `snapai-manifest-v1.6.17.json.sig`
