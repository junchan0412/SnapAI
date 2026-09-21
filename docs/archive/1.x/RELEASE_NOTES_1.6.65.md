# SnapAI 1.6.65

SnapAI 1.6.65 继续拆分 `ResultViewModel`,本轮聚焦真正发起 route 前的 request preparation。此前 VM 直接计算 privacy payload character counts、context diagnostics、payload token/image 信息、action pipeline、routing metrics snapshot、candidate routes 和 no-candidate 恢复信息。

## Request preparation coordinator

- 新增 app 层 `ResultRequestPreparationCoordinator`。
- 输入统一包含 action、source、conversation history、显式图片、capture/source context 和 privacy diagnostic。
- 输出归约为 `ready` 或 `unavailable`。
- 两种结果都携带刷新后的 privacy diagnostic,保证最终 prompt/system payload count 与当前 history 一致。

## Diagnostics 与候选路由

- context、payload 和 action-pipeline diagnostics 在同一 preparation 中构造。
- embedded image 与显式 image 合并为统一 `requestHasImage`。
- payload character/token/image 信息只计算一次并用于 route selector 与 diagnostics。
- candidate routes 使用同一 routing metrics snapshot 选择。
- 无候选时一次性生成 reason summary、recovery suggestion 和用户错误。

## 清理与架构

- 删除 VM 的 `refreshSubmissionPayloadCharacterCounts`。
- VM 不再直接调用 context/payload/pipeline diagnostic factory、route candidates 或 payload count helper。
- `runStream` 仅构造 input、解释 ready/unavailable 并进入 route attempt。
- `ResultViewModel` 从 664 行降至 626 行。
- VM 行数门禁收紧到 630,preparation coordinator 上限为 140 行。
- `SnapAILogic` 保持 44 个真实源码、36 个 symlink。

## 验证

- 原有 payload counts、privacy diagnostic、no-candidate recovery 与 routing tests 持续通过。
- remediation gate 禁止 preparation 逻辑回流 VM。
- logic suite、SwiftPM build 与 macOS smoke 通过。

## Release 资产

- `SnapAI-v1.6.65.zip`
- `snapai-manifest-v1.6.65.json`
- `snapai-manifest-v1.6.65.json.sig`
- `snapai-sbom-v1.6.65.json`
