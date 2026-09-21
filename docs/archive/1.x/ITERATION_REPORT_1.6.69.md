# SnapAI 1.6.69 迭代报告

## 代码级性能证据

旧完成态渲染有两层同步工作：

1. `MarkdownView.body` 每次执行都调用 `MarkdownParser.parse(text)`，按完整输出逐行扫描并创建 block/String 数组。
2. `view(for:)` 每次构建 heading、paragraph、list item 或 quote 时再次调用系统 inline Markdown parser，创建新的 `AttributedString`。

`.equatable()` 只能减少输入完全相等时的部分重算，不能把重工作从 body 移出，也不能为 presentation 建立明确的生命周期。

## Presentation snapshot

新 `MarkdownPresentationBuilder` 把 block parsing 与 inline parsing 合并为一个纯函数。输出 block 直接携带 `AttributedString`；code block 保留 raw code 和 language。SwiftUI 不再保存 raw block 中间态，也不执行 parser。

parser 行为保持原有边界：

- 连续段落、引用和列表归并。
- 1–6 级 ATX heading。
- fenced code language 与正文保持原样。
- inline parser 失败时保留原始文本。

## 后台与 stale protection

`MarkdownPresentationModel.refresh` 在 serial user-initiated queue 上构建。每次请求记录 generation 和 source text；主线程发布前通过 `MarkdownPresentationRefreshPolicy` 同时核对两者。

因此用户快速 regenerate、切换动作或重发时，即使旧长文本晚完成，也不会覆盖新结果。model 只发布一个 `Result(sourceText, presentation)` snapshot，不存在 source 已更新但 presentation 仍属于旧文本的中间状态。

## 布局与滚动

后台构建期间先使用纯文本 fallback，保证完成态立即可读。presentation 发布会改变字体、段间距和 code block 高度，因此 `MarkdownView` 通过 ready callback 通知 `ResultView` 再执行一次最终滚动，确保底部对齐基于最终布局。

## 结果

- `MarkdownView`:256 → 130 行。
- presentation model:44 行。
- logic presentation/builder:187 行。
- logic target:46 → 47 个真实源码；symlink 保持 36 个。
- build、logic suite 和 remediation gate 首轮通过。

当前环境没有可用的 `xctrace`，因此本轮只声明已删除的同步 body 工作和行为测试结果，不将其表述为 Instruments 实测帧率或延迟降幅。本轮没有触发真实 provider streaming。
