# SnapAI 1.6.53 迭代报告

## 背景

1.6.52 审计确认 `SnapAILogic` 仍有 41 个 symlink。候选中没有真正 isolated 的文件,因此继续“直接移动单文件”会产生 app-local 与 library 同名类型不一致。本轮选择两个可以通过现有 descriptor/轻量 DTO 修复的边界,确保迁移后真的删除重复代码。

## WriteBackCommand 迁移

- 原实现直接接受 `TextWriteBackRecord`,导致同一文件必须在 app 和 library 两个 module 中编译。
- 新实现只接受 `WriteBackCommandInput`,包括撤销标题、操作类型、诊断摘要和可用状态。
- app bridge 负责读取 AppKit 关联的 target app、过期状态等运行信息,library 只负责纯命令描述逻辑。
- app 端重复源码已删除,门禁要求 library 文件必须为真实源码。

## MenuCoordinator 去重

- `MenuCoordinator` 是 `NSMenu` adapter,不应属于核心 logic target。
- 模型菜单原先重复实现供应商启用过滤、模型启用过滤、名称脱敏和当前模型判断。
- 现在 app adapter 复用 `ModelSwitchCommandFactory.descriptors`,只负责将 descriptor 渲染成 `NSMenuItem`。
- logic test 不再依赖 AppKit `NSMenu`,改为测试 descriptor 输出和空模型行为。

## 结果

- symlink:41 → 39。
- 真实源码:36 → 37。
- 删除 app 重复命令源码 1 个。
- 删除 logic target 中不应存在的 AppKit UI symlink 1 个。
- 模型切换菜单和命令面板共享同一业务规则。

## 验证

- remediation gate:通过。
- logic suite:通过。
- SwiftPM build:通过。
- macOS smoke:通过。
