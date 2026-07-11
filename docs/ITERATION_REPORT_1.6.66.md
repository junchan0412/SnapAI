# SnapAI 1.6.66 迭代报告

## 问题定位

流式输出已经通过 leaf observable 避免整棵结果窗口 invalidation，也已在 streaming 阶段停用完整 Markdown parse；但 VM 内仍存在两类高频成本：

1. Timer 每次 tick 都创建一个 `Task { @MainActor ... }`，最快模式约每 8ms 执行一次。
2. `output += nextText` 经 forwarding getter/setter 读取旧完整文本，再调用 replace 写回，使增量展示路径仍以完整 String 作为更新单位。

VM 还直接维护 accumulator、buffer、streamDone、Timer 和 completion drain，route fallback、cancel、error 与 success 都需要了解这些内部状态。

## 生命周期归约

`ResultStreamingLifecycle` 将 provider 与 presentation 两个进度合并为一个可测试状态机：

- `appendContentToken` 负责 visible/thinking 分离，并按展示模式返回新增 visible delta 或进入 buffer。
- `finish` 冲刷半截 think tag，同时只标记 provider 已结束。
- `dequeue` 返回 `.waiting`、`.chunk` 或 `.finished`；只有 provider 结束且 buffer 为空时才完成。
- `reset` 同时释放 accumulator、thinking、pending chunks 和 finished 状态。

这避免 route fallback 只清理部分字段，也让结束语义不再依赖 VM 中多个布尔值的组合。

## Timer 与输出 publication

app 层 coordinator 持有主 run loop Timer，并通过 `MainActor.assumeIsolated` 直接执行 tick，删除逐 tick Task 分配。Timer block 弱引用 coordinator；停止时主动 invalidate Timer 并清空 callback，避免结果窗口生命周期结束后继续持有回调。

`ResultOutputState.append` 在 leaf observable 内追加 provider delta 或 typewriter chunk。调用方不再先取得完整 String 再经 forwarding setter 替换；SwiftUI 仍只观察 output leaf，thinking 与根 VM 不会被连带 invalidation。

## 结果

- `ResultViewModel`:626 → 585 行。
- streaming coordinator:82 行。
- streaming lifecycle:70 行。
- logic target:44 → 45 个真实源码；symlink 保持 36 个。
- 新增/扩展测试覆盖 lifecycle 与增量 publication。
- build、logic suite 和 remediation gate 首轮通过。

当前环境没有可用的 `xctrace`，因此本报告只陈述代码级成本删除与行为测试结果，不将其表述为 Instruments 实测帧率或内存降幅。发布前继续执行 macOS smoke 和签名 preflight；本轮不触发会向第三方发送内容的真实 provider streaming。
