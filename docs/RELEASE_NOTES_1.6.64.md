# SnapAI 1.6.64

SnapAI 1.6.64 聚焦 `ResultViewModel.runRoute` 的路由职责拆分。此前 route preflight、scoped settings、fallback 决策、diagnostics 标记与 routing metrics 写入都位于网络 streaming closure 周围,成功分支还因 typewriter 开关复制了整套完成记录代码。

## Route preparation

- 新增 app 层 `ResultRouteAttemptCoordinator`。
- route preparation 统一返回 `advance`、`unavailable` 或 `ready`。
- preflight 不适配 route 会携带更新后的 diagnostics 和切换提示推进下一候选。
- scoped settings 失效时统一跳过;没有下一候选时返回明确错误。
- ready attempt 打包 index、route、diagnostics、scoped settings 与 route note。

## Success / failure recording

- success elapsed 只计算一次。
- 同一 elapsed 同时用于 diagnostics attempt 和 `RoutingMetricsStore`。
- failure 统一调用 `FallbackRunner`,记录失败 metrics 并返回 failed diagnostics。
- VM 不再直接调用 `AIRequestRouter.scopedSettings`、`FallbackRunner.routeFailure` 或 routing metrics success/failure 写入。

## 冗余清理

- typewriter 与非 typewriter 成功分支共享 diagnostics/metrics 记录。
- 非 typewriter 仅追加立即显示和完成持久化步骤。
- 不可用 route 不再先发布短暂 running 状态再发布 skipped,减少无意义 UI flicker。
- `ResultViewModel` 从 691 行降至 664 行。
- VM 行数门禁由 700 收紧到 670,coordinator 上限为 140 行。

## 验证

- 原有 preflight skip、fallback 和 routing diagnostics logic tests 持续通过。
- remediation gate 禁止 scoped settings、fallback decision 或 metrics write 回流 VM。
- logic suite、SwiftPM build 与 macOS smoke 通过。
- `SnapAILogic` 保持 44 个真实源码、36 个 symlink。

## Release 资产

- `SnapAI-v1.6.64.zip`
- `snapai-manifest-v1.6.64.json`
- `snapai-manifest-v1.6.64.json.sig`
- `snapai-sbom-v1.6.64.json`
