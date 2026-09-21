# SnapAI 1.6.73 迭代报告

## 问题证据

1.6.72 的流式性能优化已经降低了文本状态发布频率，但运行态检查发现：

1. 结果面板和流式视觉仍会在系统开启 Reduced Motion 时持续动画。
2. 流式进度条按 60Hz 持续刷新，对短文本请求来说是没有必要的绘制成本。
3. 动作库、配置迁移和权限诊断的提示分别用独立 `asyncAfter` 清理。连续操作时，旧任务可能清掉刚显示的新提示。
4. Command Line Tools 的 SwiftUI SDK 可导入 SwiftUI，却可能没有 `SwiftUIMacros`，导致 `@State` 编译错误与实际代码问题混淆。

## 实施边界

- 用系统 `accessibilityReduceMotion` 和 `accessibilityDisplayShouldReduceMotion` 统一控制 SwiftUI/AppKit 动画。
- 将进度条刷新频率调整为 30Hz；Reduced Motion 使用固定中段进度块。
- 用 `SnapAITransientState` 集中管理瞬时状态、取消旧 `DispatchWorkItem` 并使用弱引用避免延迟任务保留视图。
- 新增 `scripts/configure-swift-toolchain.sh`，先做最小 `@State` macro probe，再自动查找 Spotlight/`/Applications` 中的完整 Xcode。

## 回归保护

- 审计门禁覆盖 Reduced Motion、可取消提示状态和 toolchain preflight 约束。
- 逻辑测试保持全绿。
- 完整 Xcode 下 `swift build` 严格并发检查通过；仓库已有的 Swift 6 concurrency warnings 仍记录为后续迁移项，本轮没有扩大告警面。
- app bundle 使用稳定自签名构建并通过启动 smoke。
