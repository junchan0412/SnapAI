# SnapAI 1.6.67

SnapAI 1.6.67 继续拆分 `ResultViewModel`,本轮聚焦 source resend、动作/语言切换与 follow-up 发送前的 submission preparation。此前 VM 同时维护 conversation history、首次图片暂存，并在 source 与 follow-up 两条路径重复构造无脱敏 handler 时的 privacy risk/diagnostic。

## Submission coordinator

- 新增 app 层 `ResultSubmissionCoordinator`。
- source resend、语言切换、动作切换与 follow-up 共用一个 `prepare` 入口。
- 外部 privacy preview handler 存在时保持原确认流程；不存在时使用统一 passthrough factory。
- coordinator 单点持有 conversation messages，并负责 initial request message 构造与 follow-up append。
- route preparation 与 provider stream 均读取同一 messages snapshot，避免 VM 分散写入。

## Privacy passthrough

- 新增 `PrivacyPreparedSubmission.passthrough`。
- 普通内容保持原文并生成低风险 diagnostic。
- 即使未启用脱敏/预览，secret-bearing 内容仍执行风险识别。
- 高风险且配置完整历史时，继续自动降级为 metadata-only，并保护 conversation export 正文。
- source/follow-up 不再维护两份逐字段相同的 diagnostic factory。

## 内存与状态清理

- 删除 VM 的 `history` 数组，由 coordinator 统一持有。
- 删除 `pendingImageData` 与 `pendingImageMimeType`；首次图片直接交给 request session。
- VM 不再额外保留仅用于下一行 initial message 构造的图片引用。
- resend/switch 不再先清空再重新写入 history，initial request 直接替换 coordinator snapshot。

## 架构结果

- `ResultViewModel` 从 585 行降至 535 行，门禁收紧到 540 行。
- `ResultSubmissionCoordinator` 为 49 行，门禁上限 70 行。
- remediation gate 禁止 history、pending image、privacy risk factory 和 `RequestSession` 组装回流 VM。
- `SnapAILogic` 保持 45 个真实源码、36 个 symlink。

## 验证

- 新增 passthrough privacy regression test，覆盖普通文本、secret-bearing 高风险、metadata-only history 与 export protection。
- 现有 follow-up、source resend、payload count、routing 与 privacy suites 持续通过。
- logic suite、SwiftPM build、macOS smoke 与签名 release preflight 均纳入发布验证。

## Release 资产

- `SnapAI-v1.6.67.zip`
- `snapai-manifest-v1.6.67.json`
- `snapai-manifest-v1.6.67.json.sig`
- `snapai-sbom-v1.6.67.json`
