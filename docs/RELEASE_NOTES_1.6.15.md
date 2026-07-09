# SnapAI 1.6.15

SnapAI 1.6.15 继续处理审计报告中 `AppSettings` 职责过宽的问题。本版不改变配置格式或用户可见设置行为,重点把导入/导出与 sanitize 逻辑从主模型文件中拆出。

## 改进

- 新增 `AppSettingsImportSanitization`,集中承载配置导出、导入配置归一化、Provider/Action/History/Privacy/Context 清洗、尺寸/历史/temperature clamp 等纯逻辑。
- `Settings.swift` 从 1000 行降到约 480 行,更聚焦 Codable 主模型、初始化、迁移入口和运行时状态。
- 新逻辑文件同步进入 `SnapAILogic` symlink manifest,继续被逻辑测试和 release preflight 覆盖。
- 保持 `providerIDAfterProviderSanitization` 对主 decoder 可见,避免拆分后破坏 provider/model 映射迁移。

## 发布资产

- `SnapAI-v1.6.15.zip`
- `snapai-manifest-v1.6.15.json`
- `snapai-manifest-v1.6.15.json.sig`
