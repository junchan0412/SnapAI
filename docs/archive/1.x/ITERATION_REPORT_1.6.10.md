# SnapAI 1.6.10 迭代报告

## 背景

1.6.9 已完成审计报告第一组修复,但 `SettingsView` 仍是最大 UI 文件。报告建议继续按 section 拆分,优先处理 Provider、Action、Privacy、Import/Export 等变化频繁区域。

## 本轮目标

- 把动作与快捷键设置从 `SettingsView` 中独立出来。
- 保持动作设置现有行为不变。
- 继续降低设置页后续迭代的变更半径。

## 实现摘要

- 新增 `Sources/SnapAI/ActionSettingsSection.swift`。
- 迁移动作工具栏、动作模板导入导出、恢复默认快捷键、快捷提问面板快捷键、动作卡片、动作编辑器和快捷键冲突跳转。
- `SettingsView` 只保留 `ActionSettingsSection(settings:navigation:ui:commit:applyCommit:)` 组合入口。
- 这次 UI-only 文件不加入 `SnapAILogic` symlink manifest,避免再次扩大逻辑 target 边界。

## 验证

- `swift build` 通过。

## 后续建议

- 下一步继续拆 `ProviderSettingsSection` 和 `HistorySettingsSection`。
- 之后再推进 SnapAILogic 的真实 library target 迁移,逐步替代 symlink 镜像。
