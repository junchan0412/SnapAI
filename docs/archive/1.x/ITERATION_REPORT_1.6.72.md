# SnapAI 1.6.72 迭代报告

## 问题证据

1.6.71 已修好结果窗误关和空选模态打扰,但高频交互仍有三类卡顿来源:

1. 流式 token / 打字机 chunk 每次 `append` 都立即发布 `@Published`,SwiftUI 观察者刷新过密。
2. 浮动面板每次 `show()` 都新建 `NSHostingView`,SwiftUI 状态树重复构建。
3. 命令面板在 `body` 内实时重算 ranked 过滤,键盘上下移动与输入同时发生时成本偏高。

## 合并发布边界

`ResultOutputState` 改为“接收增量立即入队,runloop 末尾一次 flush”的模型。这样同一帧内多个 chunk 只会触发一次 leaf observer 更新。`ResultThinkingState` 对高频整段替换提供 `replaceCoalesced`,只保留最新 pending 值。结束、取消、路由切换和 `completeText` 读取路径都会先 flush,避免导出/历史落盘看到半帧缓冲。

## 面板复用

`FloatingPanelController`、`QuickInputController` 与 `CommandPaletteController` 在首次创建后保留 panel 与 hosting。后续 show 只更新 `rootView` 与定位,并复用统一淡入淡出。这减少了冷启动式 SwiftUI 树构建,也让关闭再开更接近“唤醒”而不是“重建”。

## 命令面板缓存

过滤排序结果缓存到 `CommandPaletteModel.filteredItems`。query 变化时重算一次;键盘导航只移动 selection。视图 body 不再每次从完整 items 重新 ranked。

## 回归保护

- live output isolation 测试覆盖合并发布语义。
- auto-scroll 预算测试改为基于 `streamingMinimumInterval`。
- release preflight 继续覆盖 logic tests、macOS smoke、稳定签名、manifest/SBOM 与 zip 验证。

本轮未向第三方 provider 发送真实用户内容。性能结论限定为减少 invalidation 次数、降低面板重建和过滤重算;不声明未测量的延迟百分比。
