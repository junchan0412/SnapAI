# SnapAI 1.6.59 迭代报告

## 问题定位

`ResultViewModel.output` 在最快 typewriter 配置下可约每 8ms 更新一次。旧 `ResultView` 会在每次更新时重新执行完整 Markdown block parse、重建所有 `AttributedString`,同时启动 0.1 秒滚动动画。随着结果增长,单次工作量线性上升,重叠动画数量也会快速累积。

## 渲染分层

新的 `ResultContentRenderMode` 将生命周期拆为四种明确状态:

- `empty`:没有结果且未生成,不创建内容 renderer。
- `waiting`:请求已开始但尚无输出,只展示状态与 cursor。
- `streamingText`:用原生 `Text` 展示持续增长的字符串。
- `markdown`:生成结束后一次性解析和展示完整 Markdown。

这样把完整 Markdown parse 从“每个字符批次一次”收敛为“完成时一次”。`MarkdownView.equatable()` 进一步阻止父视图无关更新穿透相同文本边界。

## 滚动调度

- `ResultAutoScrollPolicy` 将 streaming 滚动限制为最低 33.3ms 间隔。
- 节流时间保存在 `ResultViewModel` 的非 `@Published` 字段中,不会引起额外 SwiftUI invalidation。
- streaming 阶段直接对齐底部,不创建重叠动画。
- `isStreaming` 结束时执行一次短动画,确保最终 Markdown 布局完成后落到底部。

## 分配收敛

`MarkdownView` 原先对 block 和列表执行 `Array(collection.enumerated())`。新实现直接遍历 `indices`,避免每次 body evaluation 为相同内容额外分配三个临时数组。

## 结果

- streaming 阶段完整 Markdown parse:每 tick 1 次 → 0 次。
- 自动滚动调度上限:最高约 125Hz → 30Hz。
- streaming 滚动动画:每次输出增长 1 个 → 0 个;完成时保留 1 个最终动画。
- logic target:40 → 41 个真实源码;symlink 保持 36 个。
- logic suite、SwiftPM build、macOS smoke 与 remediation gate 均通过。

真实供应商 streaming 请求会向第三方发送内容,本轮未在无用户授权的情况下触发;交互验证使用静态审计、logic policy 测试、完整构建和无网络副作用 smoke 覆盖。
