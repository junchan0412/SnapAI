# SnapAI 1.6.2 迭代报告

## 目标

1.6.2 延续 1.6.1 的主链路稳定性工作,针对“在其他 App 右键选中文本后触发 SnapAI 服务,偶发提示未检测到选中文字”的真实使用场景继续加固。同时整理测试结构,降低后续维护成本。

## 已完成

- Services fallback 目标锁定:服务入口会先记录调用瞬间的目标应用;如果 Services pasteboard 没有文本,后续 Accessibility/剪贴板兜底会优先使用这个目标,而不是重新猜测前台 App。
- 临时菜单收起:Services fallback 进入剪贴板复制前会主动收起右键菜单等 transient UI,避免菜单窗口仍然拦截 `Command + C`。
- 目标解析补强:新增 `serviceInvocation` 目标来源,旧的 frontmost/lastExternal 解析逻辑保持兼容。
- UI 清理:移除设置页已经不用的旧路由列实现,保留当前更自然的摘要、策略和诊断 disclosure 结构。
- 测试拆分:将 `Tests/SnapAILogicTests/main.swift` 拆为领域文件,包括 `UpdateCheckerTests.swift`、`RoutingTests.swift`、`PrivacyTests.swift`、`WriteBackTests.swift`、`CommandPaletteTests.swift`、`SettingsMigrationTests.swift` 和 `HistoryTests.swift`。

## 风险控制

- 普通快捷键取词路径不强制收起临时 UI,避免改变高频热键体验。
- Services fallback 新增专门测试,覆盖“服务调用目标优先”和“同一目标进程的右键菜单也可强制收起”两个边界。
- 继续保留剪贴板快照保护;当用户剪贴板内容过大或格式过多时,仍会取消自动复制/粘贴并给出诊断。
- 发布链路继续要求稳定自签名证书、签名 manifest、zip SHA256、bundle id 和 designated requirement 校验。

## 验证结果

- 逻辑测试通过:`SnapAILogicTests passed`
- SwiftPM 构建通过
- `Resources/Info.plist` 语法通过
- `git diff --check` 通过

## 发布包

完整 release 包应包含:

- `SnapAI-v1.6.2.zip`
- `snapai-manifest-v1.6.2.json`
- `snapai-manifest-v1.6.2.json.sig`

