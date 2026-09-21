# SnapAI 1.6.12

SnapAI 1.6.12 继续按 2026-07-08 全量审计报告推进设置页可维护性优化。本版不改变 AI 配置、模型选择或路由策略的用户行为,重点把供应商/模型/路由相关 UI 从主设置视图中拆出。

## 改进

- 新增 `ProviderSettingsSection`,集中承载 AI 配置概览、供应商列表、模型加载、连接测试、路由策略和高级参数。
- `SettingsView` 从审计时的近 2000 行继续下降到约 450 行,现在主要负责设置窗口导航、标题栏、置顶按钮和各 section 编排。
- Provider 设置区继续复用既有 `commit`、`applyCommit` 和 `onChange` 保存链路,避免拆分过程中改变配置持久化行为。
- 新文件保持在 app UI target 内,不加入 `SnapAILogic` symlink manifest,继续维持逻辑测试 target 的边界。

## 发布资产

- `SnapAI-v1.6.12.zip`
- `snapai-manifest-v1.6.12.json`
- `snapai-manifest-v1.6.12.json.sig`
