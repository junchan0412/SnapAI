# SnapAI 1.6.13 迭代报告

## 背景

1.6.12 已将 AI Provider/Model/Routing 设置拆出,但 `SettingsView` 仍直接承载历史记录列表、使用统计、历史保存模式和复制按钮逻辑。审计报告建议继续按 section 拆分,减少主设置视图的变化原因。

## 本轮目标

- 把历史设置 UI 从 `SettingsView` 拆出。
- 保持历史保留数量、清空历史、清空统计、保存内容模式和复制历史输出行为不变。
- 继续降低主设置视图体积和跨 section 回归风险。

## 实现摘要

- 新增 `Sources/SnapAI/HistorySettingsSection.swift`。
- `SettingsView.historyTab` 改为组合 `HistorySettingsSection(settings:commit:)`。
- 迁移历史使用统计、历史控制区、保存内容 segmented picker、空状态、历史行和 pasteboard 复制逻辑。

## 验证

- `swift build`
- 后续 release preflight 会继续覆盖逻辑 target manifest、逻辑测试、macOS smoke、release build、签名、manifest 签名和 zip 校验。

## 剩余风险

设置页职责拆分仍未全部完成。下一步可以拆出通用设置或权限设置,随后再处理 `AppSettings` 的模型/迁移/导入导出职责收敛。
