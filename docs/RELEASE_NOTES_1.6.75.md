# SnapAI 1.6.75

SnapAI 1.6.75 是一次面向日常高频操作的 UI/UX、稳定性与发布质量改进版本。

## UI 与 UX

- 新增语义化 surface、focus 和最小命中区域令牌,结果面板、操作反馈与设置控件的层次更一致。
- 结果面板主操作按钮统一 30pt 命中区域,并补齐“更多结果操作”等 VoiceOver 语义标签。
- 快捷提问面板支持 420-620pt 自适应宽度,长文本和窗口缩放时不再被固定宽度挤压。

## 稳定性

- 截图进行中会锁定发送和粘贴图片,回车提交也会被状态机拒绝,避免重复捕获和结果覆盖。
- 历史删除、收藏、标签编辑和清空失败时展示错误反馈,避免内存状态与 SQLite 状态分叉后静默继续。

## 性能

- 继续沿用增量 `TypewriterBuffer`、合并发布的 `ResultOutputState` 和节流自动滚动路径,本版将新增 surface 令牌接入保持在渲染层,不增加流式状态更新频率。

## 验证

- `scripts/run-audit-remediation-check.sh`
- `scripts/run-logic-tests.sh`
- `./build.sh`
- `scripts/run-macos-smoke-tests.sh --skip-logic`
- release preflight、签名、manifest、SBOM 与 zip 校验
