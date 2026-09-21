# SnapAI 1.6.13

SnapAI 1.6.13 继续处理 2026-07-08 全量审计报告中关于设置页职责过宽的问题。本版不改变历史记录的用户行为,重点把历史 UI 从主设置视图中拆出。

## 改进

- 新增 `HistorySettingsSection`,集中承载历史记录列表、使用统计、历史保留数量、保存内容策略和复制历史输出。
- `SettingsView` 进一步收敛为设置窗口导航与 section 编排层,降低历史功能改动影响 AI、动作、通用和权限设置的概率。
- 历史输出复制逻辑留在历史设置组件内部,继续使用 macOS pasteboard 写入结果文本。
- 继续保持 `SnapAILogic` target 边界:本次新增文件只属于 app UI target,不进入逻辑 symlink manifest。

## 发布资产

- `SnapAI-v1.6.13.zip`
- `snapai-manifest-v1.6.13.json`
- `snapai-manifest-v1.6.13.json.sig`
