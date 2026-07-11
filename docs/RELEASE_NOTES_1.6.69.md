# SnapAI 1.6.69

SnapAI 1.6.69 继续优化结果窗口的完成态渲染。此前 streaming 阶段已经使用纯文本避免每个 token 重解析 Markdown，但 stream 完成后 `MarkdownView.body` 仍同步执行整段 block parse，并在每个 heading、paragraph、list item 和 quote 的 view builder 中执行 `AttributedString(markdown:)`。

## Markdown presentation

- 新增真实 logic 源码 `MarkdownPresentation` 与 `MarkdownPresentationBuilder`。
- 一次性扫描 heading、paragraph、bullet、ordered list、quote 和 fenced code。
- heading、paragraph、list item 和 quote 的 inline Markdown 在 presentation 构建期转换为 `AttributedString`。
- SwiftUI 渲染只消费 immutable presentation block，不再了解 parser。
- 空 Markdown 返回空 snapshot；malformed inline 内容回退为普通 attributed text。

## 后台构建与缓存

- 新增 app 层 `MarkdownPresentationModel`。
- 使用 user-initiated serial queue 构建 presentation，不阻塞 SwiftUI body。
- model 持有完成后的 snapshot，后续 view invalidation 直接复用。
- 相同 source text 已有 presentation 时跳过重复 refresh。
- generation 与 requested source text 必须同时匹配才发布，旧任务不能覆盖新输出。
- model 使用单一 `@Published Result` 同时发布 source 与 presentation，避免部分状态。

## 完成态 UX

- presentation 尚未就绪时先显示完整纯文本，不出现空白结果。
- Markdown snapshot 发布后触发一次最终 bottom alignment。
- 这修复了异步布局高度变化后窗口可能停在结果中段的问题。
- 最终滚动保持原有 0.12 秒 ease-out 动画。

## 架构结果

- `MarkdownView` 从 256 行降至 130 行。
- parser 和 `AttributedString(markdown:)` 从 SwiftUI 文件完全移除。
- presentation model 44 行，logic builder 187 行。
- `SnapAILogic` 真实源码从 46 增至 47，symlink 保持 36 个。

## 验证

- 新增六类 Markdown block、inline attributed content、空输入与 stale generation 测试。
- remediation gate 禁止解析逻辑回流 `MarkdownView`，并要求后台 refresh 与 ready-scroll 接线存在。
- logic suite、SwiftPM build、macOS smoke 与签名 release preflight 均纳入发布验证。

## Release 资产

- `SnapAI-v1.6.69.zip`
- `snapai-manifest-v1.6.69.json`
- `snapai-manifest-v1.6.69.json.sig`
- `snapai-sbom-v1.6.69.json`
