# SnapAI 1.6.66

SnapAI 1.6.66 继续收敛结果窗口的流式热路径。此前 `ResultViewModel` 同时管理 visible/thinking accumulator、typewriter chunk buffer、Timer、provider 完成标志与 drain 后的 completion callback；最快配置约每 8ms 触发一次 tick，并为每次 tick 创建一个额外的 `MainActor Task`。

## Streaming lifecycle

- 新增真实 logic 源码 `ResultStreamingLifecycle`。
- 统一持有 `StreamingAccumulator`、`TypewriterBuffer` 和 provider finished 状态。
- immediate 模式直接返回新增可见 delta；typewriter 模式返回增量 drain chunk，完整结果仅保留在 lifecycle 内。
- provider stream 与 UI buffer 分别完成后才产生最终 `.finished`。
- fallback/reset 会同时释放 visible、thinking 和待展示 chunk，避免跨 route 泄漏。

## 主线程热路径

- 新增 app 层 `ResultStreamingCoordinator` 管理 Timer、tick 与 drain callback。
- Timer 已在主 run loop 上执行，使用 `MainActor.assumeIsolated` 进入 actor，不再每个 tick 分配额外 Task。
- `ResultOutputState.append` 直接追加 provider delta 或 typewriter chunk，避免 VM 读取并重新替换完整结果。
- Timer 停止时会清空 callback、字符预算与 timer 引用；取消或失败会丢弃未展示队列并立即显示 provider 已返回的完整文本。

## 架构清理

- 从 `ResultViewModel` 删除 accumulator、streamDone、Timer、typewriter buffer、tick/start/stop helpers。
- route closure 只把 provider event 交给 coordinator，并更新独立 output/thinking state。
- `ResultViewModel` 从 626 行降至 585 行，门禁收紧到 590 行。
- `ResultStreamingCoordinator` 为 82 行，门禁上限 110 行。
- `SnapAILogic` 真实源码从 44 增至 45，symlink 保持 36 个。

## 验证

- 新增 lifecycle 测试覆盖 immediate、typewriter、thinking、provider/drain 双完成和 fallback reset。
- 扩展 live output state 测试，确认增量 append 只发布一次 leaf update，空 chunk 不发布。
- remediation gate 禁止 streaming 状态和逐 tick Task 分配回流 VM/coordinator。
- logic suite、SwiftPM build、macOS smoke 与签名 release preflight 均纳入发布验证。

## Release 资产

- `SnapAI-v1.6.66.zip`
- `snapai-manifest-v1.6.66.json`
- `snapai-manifest-v1.6.66.json.sig`
- `snapai-sbom-v1.6.66.json`
