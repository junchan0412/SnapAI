# SnapAI 1.6.61

SnapAI 1.6.61 聚焦结果窗口的 SwiftUI observation fan-out。此前 `ResultView` 观察单一 `ResultViewModel`,而 `output` 在最快 typewriter 配置下可约每 8ms 发布一次;每次发布都会让 header、路由信息、source editor、错误区、footer 和操作栏一起参与 invalidation。推理模型的 `thinkingText` 也存在相同问题。

## 性能与状态边界

- `output` 从 `ResultViewModel.@Published` 移入独立 `ResultOutputState`。
- `thinkingText` 移入独立 `ResultThinkingState`。
- 两个 state 各自拥有 publisher,output 更新不会通知 thinking observers,反之亦然。
- 相同文本通过 `replace(with:)` 短路,不会触发重复通知。
- `ResultViewModel` 保留兼容 forwarding property,现有 streaming、fallback、cancel 与持久化逻辑无需复制或分叉。

## UI 渲染拆分

- `ResultOutputDisplay` 只观察 output state,负责 waiting、streaming text 与完成态 Markdown。
- `ResultThinkingSection` 只观察 thinking state。
- `ResultOutputAutoScrollObserver` 是零尺寸 leaf view,output tick 不再重建完整 ScrollView hierarchy。
- `ResultActionsToolbar` 单独观察 output,使复制、替换、追加和导出可用性仍能随结果及时更新。
- toolbar 每次 evaluation 只构建一次 `ResultCommandState`,不再为每个按钮 modifier 重复创建。

## 清理与架构

- `ResultView` 从 628 行降至 524 行。
- 高频展示组件独立为 `ResultLiveOutputView.swift` 142 行。
- `ResultViewModel` 移除未使用的 `SwiftUI` import。
- 新增真实 logic source `ResultLiveOutputState.swift`。
- `SnapAILogic` 当前为 43 个真实源码、36 个 symlink。

## 测试与门禁

- publisher 测试验证 output/thinking 相互隔离。
- 回归测试验证相同文本不产生第二次通知。
- remediation gate 禁止恢复宽 `@Published output` / `@Published thinkingText`、root view 直接读取高频文本或重新合并 state。
- logic suite、SwiftPM build 与 macOS smoke 通过。

## Release 资产

- `SnapAI-v1.6.61.zip`
- `snapai-manifest-v1.6.61.json`
- `snapai-manifest-v1.6.61.json.sig`
- `snapai-sbom-v1.6.61.json`
