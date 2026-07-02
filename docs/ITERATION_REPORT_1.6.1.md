# SnapAI 1.6.1 迭代报告

## 目标

1.6.1 延续 1.6.0 的主链路稳定性工作,重点补齐真实使用中最容易打断体验的边界:右键服务菜单取词、fallback 时的 partial output 保护、历史存储 I/O 和发布文档可信度。

## 已完成

- 服务菜单取词增强:扩展 `NSSendTypes`,并让 `ServicePasteboardText` 支持系统服务菜单可能传入的多种纯文本、RTF、HTML 和 legacy pasteboard 类型。
- 右键选区失败兜底:当 Services pasteboard 没有可用文本时,仍会回退到 Accessibility 与剪贴板取词,并记录结构化诊断。
- Fallback 行为收敛:hidden thinking 可自动切换备用模型;可见 partial output 会阻止静默 fallback,避免用户看到的内容被清空。
- 历史存储减负:`AppSettings.save()` 只在历史数组实际被修正或裁剪时重写 SQLite;新增、删除、收藏和标签仍走专门的 `HistoryStore` 增量写入路径。
- 文档更新:README、版本说明和总览图同步到 1.6.1,补充固定自签名证书、签名 manifest、服务菜单和新增模块结构。

## 风险控制

- 保持无 Apple Developer 账号场景下的固定自签名证书策略,正式 release 禁止 ad-hoc 签名。
- 更新器继续验证 manifest 签名、zip SHA256、bundle id 与 designated requirement。
- 对服务菜单解析补充逻辑测试,覆盖 UTF-8/UTF-16、legacy NSString、legacy RTF 与 legacy HTML。
- 对 fallback 补充测试,确保 thinking-only 失败可以进入备用模型,而可见 partial output 不会被静默替换。

## 验证结果

- 逻辑测试通过:`SnapAILogicTests passed`
- SwiftPM 构建通过
- `Resources/Info.plist` 语法通过
- `git diff --check` 通过
- `scripts/preflight-release.sh --skip-package` 通过

## 发布注意

发布 1.6.1 前需要本机 GitHub CLI 重新认证,并保证当前分支与远端同步。完整 release 包应包含:

- `SnapAI-v1.6.1.zip`
- `snapai-manifest-v1.6.1.json`
- `snapai-manifest-v1.6.1.json.sig`
