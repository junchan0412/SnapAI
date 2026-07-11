# SnapAI 1.6.54 迭代报告

## 背景

1.6.53 已把写回命令 descriptor 迁入 `SnapAILogic`,但写回状态、撤销判断、兼容性提示和失败诊断仍集中在 AppKit `TextEditTransaction.swift` 中。该文件既负责纯规则又负责应用激活和 pasteboard 操作,导致 logic target 继续通过 symlink 重复编译整份实现。

## 写回状态拆分

- 新增 `TextWriteBackRecordState`,仅保存目标名称、目标状态、操作、文本快照和时间。
- 新增 `TextWriteBackStateResolver`,由 app adapter 把 `NSRunningApplication` 转换为 `.missing`、`.running`、`.terminated` 或 `.currentApp`。
- 撤销可用性、菜单标题、诊断摘要和恢复建议全部由纯状态计算。
- 写回和撤销 fallback diagnostic 只接收 snapshot,不再依赖 AppKit 类型。
- `TextEditTiming` 和 `TextWriteBackPayload` 进入 logic target,让粘贴准备时序与追加格式可由快速 logic suite 覆盖。

## AppKit adapter 收窄

- `TextEditTransaction.swift` 从 410 行缩减为 145 行。
- `TextWriteBackRecord` 只保留真实目标应用供激活,并按需生成 `logicState`。
- `TextEditTransaction` 只负责 AX 选区恢复、目标应用激活、模拟粘贴以及安全恢复用户剪贴板。
- `WriteBackCompatibility` 独立迁入 library,删除 app/logic 两端重复源码。

## 类型去重

- 删除 `WriteBackCommandOperation`。
- `WriteBackCommandInput`、写回记录、诊断和执行链统一使用 `TextWriteBackOperation`。
- 删除 app bridge 中 `.replace` / `.append` 的机械转换 extension。

## 结果

- symlink:39 → 37。
- 真实源码:37 → 39。
- app target 删除重复 `WriteBackCompatibility` 源码 1 个。
- AppKit 执行器减少约 265 行纯规则代码。
- 写回状态与诊断获得独立、快速、无 AppKit 运行对象的测试覆盖。

## 验证

- remediation gate:通过。
- logic suite:通过。
- SwiftPM build:通过。
- macOS smoke:通过。
