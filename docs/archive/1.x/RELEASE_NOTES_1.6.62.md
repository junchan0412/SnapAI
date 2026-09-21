# SnapAI 1.6.62

SnapAI 1.6.62 继续收窄结果窗口的 observation graph,本轮聚焦生成完成和路由诊断阶段。此前 completion 会依次写入 `elapsed`、`charCount`,diagnostics 会依次写入 full/brief text;reset 时四个字段再次连续清空,造成多次根级 `objectWillChange`。

## Completion snapshot

- `ResultCompletionMetrics` 增加公开初始化器和统一 `.empty` 值。
- 新增 `ResultCompletionState`,将 elapsed 与 characterCount 作为一个 `@Published` snapshot。
- 完成时两个指标从两次根发布变为一次 footer leaf 发布。
- 相同 metrics、重复 reset 会直接短路。
- conversation export 继续通过 VM forwarding property 读取耗时,行为保持兼容。

## Diagnostics snapshot

- full request diagnostics 与 brief diagnostics 合并为 `ResultDiagnosticTextSnapshot`。
- 路由状态更新只替换一个 value snapshot,根 `ResultViewModel` 每轮 diagnostics 从两次发布降为一次。
- reset 仅在 snapshot 非空时发布清空。
- copy、菜单 command state 与错误恢复继续使用原有 VM API。

## UI 与架构

- 新增 `ResultCompletionMetricsRow`,只观察 completion state。
- footer 的耗时、字数、隐私状态和精简诊断按钮由 39 行 leaf view 管理。
- `ResultView` 从 524 行降至 506 行。
- `SnapAILogic` 保持 43 个真实源码、36 个 symlink。

## 测试与门禁

- 测试验证 elapsed + characterCount 只发布一次。
- 测试验证相同 completion、不必要 reset 不会 republish。
- 测试验证 diagnostics snapshot 同时保存 full/brief variant。
- remediation gate 禁止恢复分离的 `@Published elapsed`、`charCount` 或 diagnostics text。
- logic suite、SwiftPM build 与 macOS smoke 通过。

## Release 资产

- `SnapAI-v1.6.62.zip`
- `snapai-manifest-v1.6.62.json`
- `snapai-manifest-v1.6.62.json.sig`
- `snapai-sbom-v1.6.62.json`
