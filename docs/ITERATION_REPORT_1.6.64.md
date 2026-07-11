# SnapAI 1.6.64 迭代报告

## 问题定位

旧 `runRoute` 同时执行:

1. route preflight skip 判断。
2. scoped settings 构造。
3. client 与 active route UI 更新。
4. token/thinking 累积。
5. fallback failure 和 metrics。
6. success diagnostics、metrics 与完成分支。

其中 success diagnostics 和 metrics 在 typewriter on/off 分支各复制一次,并分别调用两次 `elapsedMilliseconds`,使 diagnostics 和 metrics 可能采到不同毫秒值。

## Attempt 模型

`ResultRunnableRouteAttempt` 将运行一次 route 所需的稳定数据绑定在一起。`prepare` 返回三种互斥结果:

- `advance`:携带下一 index、更新后的 diagnostics 和可选 note。
- `unavailable`:携带最终 diagnostics 和用户错误。
- `ready`:携带可直接执行的 attempt。

VM 的 `runRoute` 现在只解释结果并更新 UI,实际 streaming 放入更明确的 `executeRoute`。

## 记录一致性

`recordSuccess` 先采样一次 elapsed,再同时写入 diagnostics 与 metrics。`recordFailure` 把 `FallbackRunner`、failed diagnostics 和 metrics write 组合成单一 outcome。

## 结果

- VM route preparation/metrics side-effect:移出 coordinator。
- success 重复完成记录分支:2 套 → 1 套。
- success elapsed 采样:2 次 → 1 次。
- `ResultViewModel`:691 → 664 行。
- logic target 保持 44 个真实源码、36 个 symlink。
- logic suite、SwiftPM build、macOS smoke 与 remediation gate 通过。

本轮没有修改 provider payload 或网络协议,未触发真实第三方请求。
