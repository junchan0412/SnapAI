# SnapAI 1.6.67 迭代报告

## 取证与范围选择

本轮先审计了 956 行的 `RoutingDiagnostics.swift`。该文件与 `AIRequestRoute`、`ChatMessage`、`AppSettings`、provider/model capability、fallback 和 privacy 类型形成同一个 internal symlink cluster。单文件迁移会迫使大量内部模型升级为 public API，或新增更多 app/logic 镜像，因此没有为了减少行数而制造更差边界。

随后检查 `ResultViewModel`，发现 submission 路径存在明确且独立的重复：

1. source resend 与 follow-up 分别构造相同的未脱敏 risk assessment 和 privacy diagnostic。
2. VM 直接维护 conversation history，并在多个动作入口手动清空。
3. initial request 前将图片 Data 与 MIME 暂存在 VM 字段，下一步组装后立即清除。

## 统一 preparation

`ResultSubmissionCoordinator.prepare` 接受当前 action 与可选 UI handler。handler 存在时继续执行原 preview/confirmation；handler 缺失时统一调用 `PrivacyPreparedSubmission.passthrough`。

passthrough 并不表示跳过隐私保护：它仍运行默认敏感内容检测，并保留 high-risk history downgrade、privacy tags 和 export protection，只是不凭空要求新的确认 UI。

## Conversation ownership

coordinator 现在是 messages 的单一 owner：

- `beginInitialRequest` 一次性构造并替换 initial messages。
- `appendFollowUp` 以完整 assistant result 和已准备 user text 追加对话。
- request diagnostics 和 provider stream 从同一 messages snapshot 读取。

这删除了 VM 中多处 `history = []` 与直接 `RequestSession` 变更，也让 source/action/language 重发采用相同的 conversation reset 语义。

## 内存生命周期

旧 VM 在 `start` 中把传入图片同时保存到 `pendingImageData`，随后 `sendInitial` 才读出并清空。新路径把图片作为局部参数直接传给 coordinator；request history 仍保留 stateless provider 后续对话所需的图片，但 VM 不再额外保留短生命周期引用。

## 结果

- `ResultViewModel`:585 → 535 行。
- submission coordinator:49 行。
- 删除 VM history、pending image data/mime 和两套 privacy fallback factory。
- logic target 保持 45 个真实源码、36 个 symlink。
- build、logic suite 与 remediation gate 首轮通过。

本轮没有更改 provider payload 内容、history message 顺序或真实网络协议，也没有触发向第三方发送内容的 provider streaming。发布前继续执行 macOS smoke 和签名 preflight。
