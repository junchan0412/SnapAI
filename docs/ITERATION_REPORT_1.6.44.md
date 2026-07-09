# SnapAI 1.6.44 迭代报告

## 背景

`ActionTemplateLibrary.swift` 是命令描述器小簇中最后一个 ready 候选。原实现直接暴露 `AIAction` 并调用 `AppSettings.sanitizedImportedActions`,如果直接迁移会让 logic target 继续依赖 app target 的设置模型。

## 本轮完成

- 新增 `ActionTemplateAction`,以稳定 Codable 字段承载动作模板导入导出。
- `ActionTemplateLibrary` 改为只处理模板 DTO,保留内置模板、bundle schema、legacy action array 导入、安装时 ID/名称去重和导出清洗。
- 新增 `ActionTemplateLibraryAppBridge`,由 app target 转换 `AIAction` 与 `ActionTemplateAction`。
- 设置页和命令面板的动作模板入口改为通过桥接层安装、导入和导出。
- `ActionTemplateLibrary.swift` 迁入 `Sources/SnapAILogic`,并从 app target 删除重复源码。
- 下调 `SnapAILogic` symlink 上限并提升真实源码下限。

## 当前边界状态

- `SnapAILogic` 实体 Swift 源码:27 个。
- `SnapAILogic` 剩余 symlink:49 个。
- 命令描述器小簇已完成;后续迁移需要按更大的业务簇推进。
