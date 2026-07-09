# SnapAI 1.6.46 迭代报告

## 背景

`InstallLogCommand.swift` 没有其它 symlink 消费者,但原实现直接接收 `UpdateChecker.InstallLogStatus`,并复用尚未迁移的 `PermissionHealthSnapshot.shareablePath`。直接迁移会让 logic target 继续暴露 app 更新器类型。

## 本轮完成

- 新增 `InstallLogCommandStatus`,用轻量 enum 表达安装日志的无记录、不可信路径、已过期和可用状态。
- `InstallLogCommand` 改为只依赖自身状态 DTO,并内置路径脱敏逻辑。
- 新增 `InstallLogCommandAppBridge`,由 app target 将 `UpdateChecker.InstallLogStatus` 映射为 logic 状态。
- 命令面板中的安装日志显示/复制入口改用桥接后的状态。
- `InstallLogCommand.swift` 迁入 `Sources/SnapAILogic`,并从 app target 删除重复源码。
- 下调 `SnapAILogic` symlink 上限并提升真实源码下限。

## 当前边界状态

- `SnapAILogic` 实体 Swift 源码:29 个。
- `SnapAILogic` 剩余 symlink:47 个。
- 剩余 ready 候选仍需逐个评估是否公开 app target 类型;较大簇应继续按迁移计划推进。
