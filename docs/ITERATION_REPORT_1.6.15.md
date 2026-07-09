# SnapAI 1.6.15 迭代报告

## 背景

设置 UI 在 1.6.12-1.6.14 已完成主要 section 拆分。审计报告第 2 项的剩余重点转向 `AppSettings`:主 `Settings.swift` 仍同时承载 Codable 主模型、迁移入口、导入导出、sanitize、clamp 和 provider/action/history/privacy/context 清洗。

## 本轮目标

- 把导入/导出和 sanitize 纯逻辑从 `Settings.swift` 拆出。
- 保持 Codable 字段、迁移行为和配置导入导出格式不变。
- 同步维护 `SnapAILogic` symlink manifest,避免测试 target 边界漂移。

## 实现摘要

- 新增 `Sources/SnapAI/AppSettingsImportSanitization.swift`。
- 新增 `Sources/SnapAILogic/AppSettingsImportSanitization.swift` symlink。
- 更新 `scripts/logic-symlink-manifest.txt`。
- `Settings.swift` 保留主模型、初始化、encode/decode、运行时状态和迁移入口。

## 验证

- `swift build`
- `scripts/check-logic-symlinks.sh`
- 后续 release preflight 会继续覆盖逻辑测试、macOS smoke、release build、签名、manifest 签名和 zip 校验。

## 剩余风险

`AppSettings` 仍可继续拆分:后续建议把 Codable encode/decode 或迁移流程抽到专门文件,并逐步推动真实 SwiftPM library target 替代 symlink 镜像。
