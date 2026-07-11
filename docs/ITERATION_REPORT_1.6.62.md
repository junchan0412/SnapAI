# SnapAI 1.6.62 迭代报告

## 问题定位

1. `finishMetrics` 计算一个 `ResultCompletionMetrics`,随后拆开写入两个 `@Published` property。
2. `updateRequestDiagnostics` 从同一个 diagnostics 对象生成 full/brief string,随后分两次发布。
3. `resetOutput` 无条件清空四个 published 字段,即使状态已经为空。
4. completion metrics 只影响 footer,却通过根 VM 通知整个结果窗口。

## 状态合并

`ResultCompletionState` 直接发布 `ResultCompletionMetrics`,使本来具备一致性关系的耗时与字数始终原子更新。它提供 `replace(with:)` 和 `reset()`,并以 Bool 返回是否真的发生变化,便于测试和未来协调器判断。

`ResultDiagnosticTextSnapshot` 将 full/brief text 作为一个 Equatable value。VM 对外仍暴露原属性名的只读 forwarding API,因此菜单、copy command 和 view 无需了解存储变化。

## Leaf footer

根 footer 不再读取 `vm.elapsed` / `vm.charCount` 做条件分支。`ResultCompletionMetricsRow` 永久位于 view tree,但仅订阅 completion state;空 snapshot 返回空内容,完成发布后只重建指标行。

## 结果

- completion 根级发布:2 次 → 0 次;footer leaf 发布 1 次。
- diagnostics text 根级发布:2 次 → 1 次。
- 相同 completion/reset:发布 → 短路。
- `ResultView`:524 → 506 行。
- logic target 保持 43 个真实源码、36 个 symlink。
- snapshot publisher、去重、logic suite、SwiftPM build、macOS smoke 与 remediation gate 通过。

真实 provider streaming 未在无授权情况下触发;本轮不声明未经 Instruments 测量的 CPU、FPS 或内存百分比。
