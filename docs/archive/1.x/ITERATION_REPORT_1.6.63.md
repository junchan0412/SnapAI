# SnapAI 1.6.63 迭代报告

## 问题定位

`ResultViewModel.finishMetrics` 同时承担五类职责:

1. 防止重复完成。
2. 计算并发布耗时/字数。
3. 更新动作 usage 和 settings。
4. 保存历史且防止重复保存。
5. 判断并执行自动替换。

这些职责依赖三个分散 flag,使 fallback、cancel、retry、follow-up 的正确性必须跨多处赋值理解。

## Lifecycle

新的 `ResultCompletionLifecycle` 是无 UI 依赖的值类型。`beginCompletion` 原子地检查并标记完成;`updateHistorySaved` 使用 OR 语义保持单调;`reset` 开启新请求生命周期。

logic 测试直接证明:

- 第一次完成被接受。
- 第二次完成被拒绝。
- true history state 不会被后续 false 覆盖。
- reset 后可以再次完成。

## Coordinator

`ResultCompletionCoordinator` 由 VM 初始化并持有 `AppSettings`。它接收一个完整 `ResultCompletionContext`,按固定顺序:

1. 获取 lifecycle completion 权限。
2. 计算并发布 metrics。
3. 记录 usage。
4. 保存 history 或 settings。
5. 计算并执行 auto replace。

返回的 outcome 只包含 metrics 和是否自动写回,VM 无需重新判断副作用条件。

## 结果

- VM completion flag:3 个 → 0 个。
- VM 直接 completion side-effect 簇:约 50 行 → 20 行 context adapter。
- `ResultViewModel`:716 → 691 行。
- logic target:43 → 44 个真实源码;symlink 保持 36 个。
- lifecycle tests、logic suite、SwiftPM build、macOS smoke 与 remediation gate 通过。

本轮没有改变真实 provider 请求内容或网络协议,因此无需发起第三方请求验证。
