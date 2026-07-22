# SnapAI 1.6.72

SnapAI 1.6.72 是一次重量级性能与交互动画优化版本,聚焦流式生成主路径、浮动面板生命周期和命令面板搜索体验。目标是让高频场景更顺滑,而不是再引入新的用户流程。

## 流式性能

- 结果输出 `append` 在同一 runloop 内合并发布,避免打字机每个 tick 都触发整页 invalidation。
- thinking 增量支持合并更新,长推理文本展开时减少 Disclosure 区域重绘。
- 结束/取消/路由切换前强制 flush,保证落盘、导出和诊断读到完整文本。
- 打字机节奏改为更大 chunk + 更长间隔,并允许 timer tolerance 合并唤醒。
- 流式 auto-scroll 降到 20Hz,滚动路径禁用动画 transaction,降低与打字机刷新叠加的抖动。

## 面板生命周期

- 结果窗、快捷提问、命令面板统一淡入淡出呈现。
- 结果窗与快捷提问复用 `NSHostingView` 根树,避免每次弹出重建 SwiftUI 状态。
- 命令面板同样复用 hosting,并在关闭时清空过滤缓存。

## 命令面板与动画

- 命令面板过滤结果缓存到 model,搜索和键盘导航不再每次 body 重算排序。
- 流式进度条改为 display-linked 连续相位推进,视觉更接近原生 indeterminate。
- 打字光标改为连续相位闪烁,减少硬切换感。
- 结果窗流式状态切换增加轻量 transition。

## 验证

- `scripts/run-audit-remediation-check.sh`
- `scripts/run-logic-tests.sh`
- `scripts/check-logic-symlinks.sh`
- `swift build`
- `scripts/run-macos-smoke-tests.sh --skip-logic`
- 签名 `scripts/preflight-release.sh`

## Release 资产

- `SnapAI-v1.6.72.zip`
- `snapai-manifest-v1.6.72.json`
- `snapai-manifest-v1.6.72.json.sig`
- `snapai-sbom-v1.6.72.json`
