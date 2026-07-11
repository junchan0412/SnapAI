# SnapAI 1.6.61 迭代报告

## 问题定位

`ResultViewModel` 原有 19 个 `@Published` property。高频 `output` 与 `thinkingText` 和低频 action、route、error、footer metrics、follow-up 共用一个 `objectWillChange`,导致流式字符更新穿透整个结果窗口。

1. typewriter 最快约 125Hz,每 tick 都会发布完整 output 字符串。
2. 非 typewriter streaming 会随 provider token 直接更新 output。
3. thinking callback 和 content token extraction 会频繁写入 thinkingText,其中大量写入可能与旧值相同。
4. 操作栏需要跟随结果启用,但 header、source editor 和 footer 并不需要跟随每个字符刷新。

## 独立实时状态

新的逻辑层提供两个最小 observable:

- `ResultOutputState`:可见输出。
- `ResultThinkingState`:推理过程。

两者使用 `replace(with:)` 统一相等值短路。`ResultViewModel.output` / `thinkingText` 成为 forwarding property,因此请求、fallback 和 typewriter 状态机无需了解 SwiftUI view 的拆分细节。

## Leaf observation

结果窗口现在把高频订阅放到最小消费者:

- output display。
- thinking disclosure。
- 零尺寸 auto-scroll observer。
- 需要即时更新 command availability 的 toolbar。

根 `ResultView` 仍观察低频 VM 状态,但 child state 的 `objectWillChange` 不会自动转发到 parent VM。这使每个 token 不再触发 header、路由栏、source editor、error recovery 和 follow-up 区域的根级重建。

## 结果

- 宽 VM 高频 publisher:2 个 → 0 个。
- 独立高频 observable:0 个 → 2 个。
- 相同 thinking/output 写入:发布 → 短路。
- `ResultView`:628 → 524 行。
- logic target:42 → 43 个真实源码;symlink 保持 36 个。
- publisher isolation、相等值去重、logic suite、SwiftPM build、macOS smoke 与 remediation gate 通过。

真实 provider streaming 会向第三方发送内容,本轮未在无用户授权时触发。当前环境也没有 Instruments `xctrace`,因此不虚构帧率、CPU 或内存百分比;性能结论来自明确的 observation graph 收窄、同步 publisher 测试和构建验证。
