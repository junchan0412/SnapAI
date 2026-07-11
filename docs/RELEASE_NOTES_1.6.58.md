# SnapAI 1.6.58

SnapAI 1.6.58 聚焦路由性能数据的持久化开销。此前每次路由成功、失败或手动模型偏好都会在调用线程同步编码整张 metrics table 并原子写盘,可能阻塞请求完成和 SwiftUI 状态更新。

## 性能

- `RoutingMetricsStore` 使用独立 utility queue 持久化。
- 默认在 350ms 窗口内合并连续变化。
- generation 检查确保只有最新 snapshot 执行磁盘写入。
- 更新方法现在只在锁内修改内存快照,随后立即返回。
- JSON 编码、目录创建和原子写盘全部离开请求/UI 调用线程。

## 数据可靠性

- 新增 `flushPersistence()`。
- `applicationWillTerminate` 会等待最新 metrics 写入完成。
- flush 会推进 generation,使尚未执行的延迟任务自动失效,避免退出阶段重复写入旧 snapshot。
- 原有锁继续保护 cache 和 generation,持久化过程中不占用状态锁。

## 测试与门禁

- 12 次快速成功记录只产生一次持久化调用。
- 合并写入包含最新的 12 次结果。
- 新的失败记录在 flush 时立即保存。
- flush 后延迟任务不会再次写入。
- remediation gate 要求后台 persistence、退出 flush 和并发测试持续存在。

## 验证

- `scripts/run-audit-remediation-check.sh`
- `scripts/run-logic-tests.sh`
- `swift build`
- `scripts/run-macos-smoke-tests.sh --skip-logic`
- `scripts/preflight-release.sh`

## Release 资产

- `SnapAI-v1.6.58.zip`
- `snapai-manifest-v1.6.58.json`
- `snapai-manifest-v1.6.58.json.sig`
- `snapai-sbom-v1.6.58.json`
