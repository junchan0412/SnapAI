# SnapAI 1.6.12 迭代报告

## 背景

审计报告指出 `SettingsView` 和 `AppSettings` 聚合了过多职责。1.6.10 已先拆出动作/快捷键设置,但 AI 供应商、模型、路由诊断和连接测试仍留在主设置视图中。

## 本轮目标

- 把 AI Provider/Model/Routing 设置从 `SettingsView` 拆出。
- 保持原有保存、快捷键重注册和模型加载行为兼容。
- 继续压低主设置视图体积,为后续拆历史、权限和通用设置留下更清晰边界。

## 实现摘要

- 新增 `Sources/SnapAI/ProviderSettingsSection.swift`。
- `SettingsView` 的 AI tab 改为组合 `ProviderSettingsSection`。
- 迁移供应商菜单、模型菜单、路由策略、路由预览、供应商卡片、模型列表、连接测试、Provider 高级参数和增删移动逻辑。

## 验证

- `swift build`
- 后续 release preflight 会继续覆盖逻辑 target manifest、逻辑测试、macOS smoke、release build、签名、manifest 签名和 zip 校验。

## 剩余风险

这仍是设置页职责拆分的中间阶段。后续应继续拆出历史设置区,并逐步把 `AppSettings` 的迁移、sanitize、导入导出和运行时派生状态迁到更窄的模型/服务类型中。
