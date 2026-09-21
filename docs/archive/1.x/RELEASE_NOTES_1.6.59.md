# SnapAI 1.6.59

SnapAI 1.6.59 聚焦结果窗口的流式渲染性能与交互稳定性。此前 typewriter 输出每次增长都会重新解析完整 Markdown、重建 block 视图并启动滚动动画;长回答和高速输出时会放大 CPU、临时内存与动画调度开销。

## 性能与内存

- streaming 阶段使用轻量 `Text` 展示增量结果,不再逐 tick 调用 `MarkdownParser.parse`。
- 输出完成后才一次性切换到 `MarkdownView`。
- `MarkdownView` 增加 `Equatable` 边界,追问输入等无关状态变化不会重复构建相同内容。
- Markdown block、无序列表和有序列表改为按 collection index 遍历,不再创建临时 `Array(enumerated())`。

## UI 与 UX

- waiting 与 streaming 状态保留 typing cursor,并补充 VoiceOver 可读状态。
- streaming 自动滚动最高限制为 30Hz,避免最高约 125Hz 的 typewriter 更新直接驱动滚动。
- streaming 阶段滚动不再逐 tick 创建动画;生成完成时执行一次 0.12 秒最终对齐动画。
- 完成内容仍保留 Markdown 标题、列表、代码块和行内样式。

## 架构与门禁

- 新增真实 logic source `ResultContentPresentation.swift`,集中维护结果渲染模式和滚动策略。
- `SnapAILogic` 当前为 41 个真实源码、36 个 symlink。
- 新增 empty、waiting、streaming plain text、completed Markdown 与 30Hz scroll policy 回归测试。
- remediation gate 禁止恢复 streaming Markdown 全量重解析或逐 tick 滚动动画。

## 验证

- `scripts/run-audit-remediation-check.sh`
- `scripts/run-logic-tests.sh`
- `scripts/check-logic-symlinks.sh`
- `swift build`
- `scripts/run-macos-smoke-tests.sh --skip-logic`
- `scripts/preflight-release.sh`

## Release 资产

- `SnapAI-v1.6.59.zip`
- `snapai-manifest-v1.6.59.json`
- `snapai-manifest-v1.6.59.json.sig`
- `snapai-sbom-v1.6.59.json`
