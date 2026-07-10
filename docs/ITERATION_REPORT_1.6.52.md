# SnapAI 1.6.52 迭代报告

## 背景

本轮先对 328 个项目文件执行全量审计,再按数据一致性、性能、测试真实性和 UI/UX 的用户影响排序 remediation。审计同时确认:候选脚本仍会把部分需要 app bridge / DTO 的文件误判为可直接迁移,因此 target 边界分类也需要同步增强。

## 本轮完成

- 生成并 lint 通过 `audit-report-SnapAI-2026-07-11.md`,覆盖架构、安全、稳定性、性能、测试、UI/UX、隐私、发布等 25 个维度。
- 修复 history mutation 忽略 SQLite Bool 结果的问题,持久化失败时不再改变内存 source of truth。
- 新增失败注入测试,覆盖删除、清空、收藏和标签更新的一致性。
- 将打字机推进抽成真实 logic 源码 `TypewriterBuffer`,ResultViewModel 只追加新显示文本。
- `StreamingAccumulator` 返回可见 delta,避免 UI 再次扫描完整结果。
- 快捷输入截图增加进行中状态、重复触发 guard、禁用态和进度反馈。
- 动作/供应商 icon-only 控件增加动态 accessibility label,并通过实际 Accessibility tree 验证。
- 检测到 216 个测试声明只有 215 个注册,补回遗漏的隐私测试并增加自动门禁。
- 新增 `script/build_and_run.sh` 与 Codex Run action,真实 `.app` bundle 构建、签名和启动验证通过。
- 为 `scripts/report-logic-migration-candidates.sh` 增加 `boundary` 列。
- 将无 symlink 消费者但仍有 app/test 消费者的文件标为 `bridge` / `app-api`。
- 保留真正无消费者的 `ready` / `isolated` 状态,让后续迁移更容易挑选最小切口。
- 在 `scripts/run-audit-remediation-check.sh` 中加入 app-api 分类存在性检查,防止分析脚本退回到过粗的状态。
- 更新 `docs/LOGIC_TARGET_MIGRATION_PLAN.md` 的候选状态说明。

## 当前边界状态

- `SnapAILogic` 实体 Swift 源码:36 个。
- `SnapAILogic` 剩余 symlink:41 个。
- 剩余候选现在可分成三类:按簇迁移的 `cluster`,需要 DTO/app bridge 的 `app-api`,以及真正可直接迁移的 `isolated`。

## 验证结果

- `scripts/run-audit-remediation-check.sh`:通过。
- `scripts/run-logic-tests.sh`:通过;当前 CLT 环境使用 swiftc compatibility runner。
- `swift build`:通过。
- `scripts/run-macos-smoke-tests.sh --skip-logic`:通过,包含 pasteboard、Accessibility、Screen Recording 与 hotkey probe。
- `./script/build_and_run.sh --verify`:通过,稳定签名 app bundle 可启动。
- 冷启动后实测 RSS 约 132 MB;本轮优先消除了长输出时会持续放大的临时 String 分配路径。
