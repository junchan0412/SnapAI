# SnapAI 文档索引

更新：2026-10-25。当前源码版本为 **2.1.0**，版本以 `Resources/Info.plist` 为准。

## 从这里开始

| 目的 | 文档 |
| --- | --- |
| 安装、使用与开发命令 | [项目 README](../README.md) |
| 了解当前工程状态、检查结果和优化判断 | [项目检查与清理报告](reports/PROJECT_HEALTH_2026-10-25.md) |
| 查看下一阶段优先级与验收标准 | [当前路线图](roadmap/ROADMAP_2026-10-25.md) |
| 查看当前版本交付内容 | [2.1.0 发布说明](releases/RELEASE_NOTES_2.1.0.md) |
| 区分已经验证和仍待验证的能力 | [2.1.0 验收记录](reports/RELEASE_ACCEPTANCE_2.1.0.md) |

## 分类导航

| 目录 | 用途与主要入口 |
| --- | --- |
| `guides/` | [App Intents / Shortcuts](guides/APP_INTENTS.md)、[无障碍走查手册](guides/ACCESSIBILITY_WALKTHROUGH.md) |
| `architecture/` | [模块边界](architecture/MODULE_BOUNDARIES.md)；迁移旧计划仅供历史参考 |
| `releases/` | 当前版本说明与[发布流程](releases/RELEASE_PIPELINE.md) |
| `reports/` | 当前检查报告、版本验收及按日期保留的评估/实施过程 |
| `roadmap/` | 当前路线图，以及 [固定任务验收设计](roadmap/ROADMAP_ACCEPTANCE_2026-10-04.md)、[性能测量方法与历史记录](roadmap/ROADMAP_PERFORMANCE_2026-10-04.md) |
| `baselines/` | [启动基线](baselines/STARTUP_BASELINE.md)、[运行时内存基线](baselines/RUNTIME_MEMORY_BASELINE.md)，需按各自日期、build 配置和设备理解 |
| `performance/` | 采样 JSON、测试日志、实机观察等原始证据；[2.1.0 证据](performance/verification-20261025/) |
| `benchmarks/` | 2.0.0 存储与流式处理的原始对照数据 |
| `screenshots/` | README、发布说明和重构报告引用的演示截图 |
| `archive/` | [历史版本、旧方案及旧素材](archive/README.md) |

## 维护约定

1. 当前待办只维护在当前路线图；历史实施日志保留时间顺序，不继续充当实时状态面板。
2. 新报告使用 `主题_YYYY-MM-DD.md`，说明源码基线、检查范围、结果和限制。当前说明变化时同步本索引与 README。
3. 新版本说明放在 `releases/RELEASE_NOTES_X.Y.Z.md`，发布脚本从这里读取。旧版本转入归档时同步引用。
4. 原始证据按日期保存；保留失败样本及测量口径，不把 debug-preview、解析微基准或源码检查替代完整实机验收。
5. Markdown 使用相对路径；报告与日志分开保存，重要证据不只放在 `/tmp`。清理前检查链接、脚本依赖与文件用途。
