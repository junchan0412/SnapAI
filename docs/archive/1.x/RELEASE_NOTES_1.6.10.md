# SnapAI 1.6.10

SnapAI 1.6.10 继续按 2026-07-08 审计报告推进设置页可维护性优化。本版不改变用户可见的动作/快捷键行为,重点把动作设置从主设置视图中拆出,降低后续配置、快捷键和动作模板迭代的回归风险。

## 改进

- 新增 `ActionSettingsSection`,承接动作列表、动作编辑、快捷键录制、动作库导入导出和恢复默认快捷键。
- `SettingsView` 从约 1480 行继续降到约 1080 行,主视图更接近“窗口组装层”。
- 快捷提问面板快捷键、动作级快捷键冲突检测和“查看冲突项”跳转保留原有行为。
- 动作级供应商/模型覆盖、Thinking 模式、翻译目标语言、替换确认和历史保存开关保持兼容。

## 测试

- `swift build` 通过。
- 后续 release preflight 会继续覆盖 logic tests、macOS smoke、签名、manifest、zip 解包和版本一致性。

## 发布资产

- `SnapAI-v1.6.10.zip`
- `snapai-manifest-v1.6.10.json`
- `snapai-manifest-v1.6.10.json.sig`
