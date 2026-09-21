# SnapAI 1.6.58 迭代报告

## 问题定位

路由 metrics 会在请求成功、失败以及用户手动切换模型时更新。旧 `RoutingMetricsStore.update` 在释放锁后直接调用 `save`,因此 JSON 编码和原子文件写入仍发生在调用者线程。请求完成通常位于主状态链,高频 fallback 或模型切换会造成不必要的 UI 延迟和磁盘放大。

## 后台合并设计

- cache 更新仍使用短时 `NSLock` 保证一致性。
- 每次变化递增 `persistenceGeneration`。
- utility queue 在 350ms 后检查 generation,仅最新任务继续保存。
- snapshot 使用 Swift 值语义捕获,后续 cache 更新不会修改待保存版本。
- 保存前不持有状态锁,慢磁盘不会阻塞新 metrics 记录。

## 退出一致性

应用退出时 `flushPersistence` 获取最新 cache、推进 generation,然后在 persistence queue 上同步完成一次保存。这样既不丢失最后 350ms 数据,也不会让旧延迟任务覆盖 flush 结果。

## 结果

- 快速连续 12 次更新:12 次同步写盘 → 1 次后台写盘。
- 请求/UI 调用线程不再执行 JSON 编码和文件系统写入。
- logic suite 新增真实 queue/semaphore 并发回归覆盖。
- SwiftPM build、macOS smoke 和 remediation gate 通过。
