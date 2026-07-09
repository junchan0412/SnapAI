# SnapAI 1.6.32 迭代报告

## 背景

取词目标解析器负责在服务调用来源、前台应用和最近外部应用之间选择合适目标。它依赖 AppKit 系统类型,但不依赖 app target 中的业务模型,适合独立迁移。

## 本轮完成

- 将 `CaptureCoordinator.swift` 从 symlink 改为 `Sources/SnapAILogic` 下的真实源码。
- 删除 app target 中对应的重复源码文件。
- 将解析来源枚举和 resolver 方法公开给 app target。
- 将审计修复脚本扩展到 18 个已迁移实体源码。

## 当前边界状态

- `SnapAILogic` 实体 Swift 源码:18 个。
- `SnapAILogic` 剩余 symlink:58 个。
- 下一步继续优先迁移 app-only 消费的纯逻辑模块;涉及 `AppSettings` 或 `AIRequestRoute` 的文件需按更大依赖簇处理。
