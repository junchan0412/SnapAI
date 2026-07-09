# SnapAI 1.6.14 迭代报告

## 背景

1.6.12 和 1.6.13 已拆出 AI Provider 设置区与历史设置区。主 `SettingsView` 仍保留通用设置、权限设置和一组旧 extension helper,这些内容会继续扩大设置页改动半径。

## 本轮目标

- 拆出通用设置区。
- 拆出权限设置区。
- 删除不再使用的 `SettingsViewLayout` helper 文件。
- 保持开机启动、Dock 图标、优先 AX 取词、iCloud 同步、打字机动画、权限跳转和重新检测行为不变。

## 实现摘要

- 新增 `Sources/SnapAI/GeneralSettingsSection.swift`。
- 新增 `Sources/SnapAI/PermissionSettingsSection.swift`。
- `SettingsView` 改为组合 `GeneralSettingsSection` 和 `PermissionSettingsSection`。
- 删除 `Sources/SnapAI/SettingsViewLayout.swift`。

## 验证

- `swift build`
- 后续 release preflight 会继续覆盖逻辑 target manifest、逻辑测试、macOS smoke、release build、签名、manifest 签名和 zip 校验。

## 剩余风险

设置页 UI 组合层已经明显收敛。审计报告第 2 项的下一阶段应转向 `AppSettings` 职责拆分,尤其是迁移、sanitize、导入导出、派生状态和运行时保存策略。
