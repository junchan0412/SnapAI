# SnapAI 1.6.24

SnapAI 1.6.24 开始推进审计报告中 `SnapAILogic` target symlink 边界问题的真实迁移。本版先迁移两块低耦合逻辑源码,让 app target 正式依赖 `SnapAILogic` library target。

## 改进

- `SnapAI` executable target 新增对 `SnapAILogic` 的依赖。
- `ResultRouteStatusText` 移入 `Sources/SnapAILogic` 实体源码,并从 app target 删除同名文件。
- `TextDiff` 移入 `Sources/SnapAILogic` 实体源码,并从 app target 删除同名文件。
- `DiffPreviewWindow` 和 `ResultView` 改为通过 `import SnapAILogic` 使用已迁移逻辑类型。
- `build.sh` 新增 `SnapAILogic` module/object 编译步骤,确保手工 release bundle 构建与 SwiftPM target 结构一致。
- `scripts/check-logic-symlinks.sh` 更新为 source manifest 检查,支持 symlink 和已迁移实体源码共存。
- `scripts/run-audit-remediation-check.sh` 新增迁移防回退检查,确保已迁移文件不会重新变成 symlink 或被 app target 重复编译。

## 发布资产

- `SnapAI-v1.6.24.zip`
- `snapai-manifest-v1.6.24.json`
- `snapai-manifest-v1.6.24.json.sig`
- `snapai-sbom-v1.6.24.json`
