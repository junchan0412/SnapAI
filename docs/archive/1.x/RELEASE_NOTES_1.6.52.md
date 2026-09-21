# SnapAI 1.6.52

SnapAI 1.6.52 完成新一轮全量审计与 remediation。本版重点提升历史数据一致性、长文本流式渲染效率、截图交互反馈、辅助功能语义和测试真实性,并继续推进 `SnapAILogic` target 边界治理。

## 改进

- 历史删除、清空、收藏和标签编辑改为 SQLite 持久化成功后再提交内存状态,失败时不再伪装成功。
- 新增 `SnapAILogic.TypewriterBuffer`,打字机效果按未展示 chunk 增量推进,不再每个 tick 从完整字符串开头重新索引和复制前缀。
- `StreamingAccumulator` 直接返回新增可见文本,thinking tag 跨 chunk 时仍保持正确分离。
- 快捷输入截图增加 `isCapturing` single-flight 状态、禁用态和 `ProgressView`,避免重复排队和窗口反复隐藏。
- 动作与供应商排序、展开和添加模型按钮补齐包含对象名称的动态 accessibility label。
- 新增 Codex Run action 和 `script/build_and_run.sh`,统一 kill、release-style build、app bundle 启动与进程验证。
- logic test 注册门禁自动比较测试声明和 `runAllLogicTests`,并补回漏执行的 expanded secret format 隐私测试。
- `scripts/report-logic-migration-candidates.sh` 新增 `boundary` 列。
- 候选状态从原来的 `blocked` / `ready` 扩展为:
  - `blocked` / `cluster`:仍有 symlink 消费者,需要按簇迁移。
  - `bridge` / `app-api`:没有 symlink 消费者,但 app/test 仍直接消费,迁移前需要 DTO 或 app bridge。
  - `ready` / `isolated`:未检测到 symlink 或 app/test 消费者,可作为最小候选。
- 审计门禁新增候选分析 app-api 风险分类检查。
- `docs/LOGIC_TARGET_MIGRATION_PLAN.md` 更新剩余候选状态解释。
- `SnapAILogic` 真实源码基线从 35 提升到 36。
- README 与 UI 总览同步到 1.6.52,并修正不存在许可证文件的误导性说明。

## 验证

- `scripts/report-logic-migration-candidates.sh`
- `scripts/run-audit-remediation-check.sh`
- `scripts/check-logic-symlinks.sh`
- `scripts/run-logic-tests.sh`
- `swift build`
- `scripts/run-macos-smoke-tests.sh --skip-logic`
- `./script/build_and_run.sh --verify`
- `scripts/preflight-release.sh`

## Release 资产

- `SnapAI-v1.6.52.zip`
- `snapai-manifest-v1.6.52.json`
- `snapai-manifest-v1.6.52.json.sig`
- `snapai-sbom-v1.6.52.json`
