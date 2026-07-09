# SnapAI 1.6.25

SnapAI 1.6.25 继续推进 `SnapAILogic` target 的真实源码迁移。本版将追问输入行为和追问历史导航逻辑移入 library target,进一步减少 symlink 镜像面。

## 改进

- `FollowUpInputBehavior` 移入 `Sources/SnapAILogic` 实体源码,并从 app target 删除同名文件。
- `FollowUpHistoryStore` 移入 `Sources/SnapAILogic` 实体源码,并从 app target 删除同名文件。
- `ResultViewModel` 显式 `import SnapAILogic`,使用已迁移的追问历史类型。
- `scripts/run-audit-remediation-check.sh` 新增追问输入/历史迁移防回退检查。
- `SnapAILogic` 当前为 4 个实体 Swift 源文件 + 72 个剩余 symlink。

## 发布资产

- `SnapAI-v1.6.25.zip`
- `snapai-manifest-v1.6.25.json`
- `snapai-manifest-v1.6.25.json.sig`
- `snapai-sbom-v1.6.25.json`
