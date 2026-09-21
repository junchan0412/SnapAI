# SnapAI 1.6.9

SnapAI 1.6.9 是一次审计修复与发布门禁补丁版本,对应 2026-07-08 全量审计报告的第一组闭环项。重点是降低配置持久化、测试真实性、供应链和 target 边界风险。

## 改进

- API Key 不再依赖 macOS Keychain,改为本机 Application Support 下的 AES.GCM 加密密钥存储。
- 本地密钥目录、master key 和密文文件会收紧到 `0700` / `0600` 权限。
- 权限健康中心和诊断文本新增本地密钥存储状态,保存失败会进入诊断信息。
- 设置页继续拆分:隐私、上下文包、配置导入导出从主设置视图移到独立组件。
- CI checkout pin 到 immutable SHA,降低 GitHub Actions tag 漂移风险。
- 新增 SnapAILogic symlink manifest 校验,防止 UI/AppKit-only 文件误入逻辑测试 target。
- release unsafe optimization flags 已移除,使用 SwiftPM 标准 release 配置。

## 测试

- 新增本地加密密钥存储落盘加密与权限测试。
- 新增 prompt/privacy/fallback eval 语料测试,覆盖本地隐私优先、云端 fallback、高风险预览、脱敏和历史保护。
- 新增 macOS smoke 脚本,覆盖逻辑 target 边界、逻辑测试、剪贴板 roundtrip/restore 和权限探测。

## 升级注意

旧版本保存在 Keychain 中的 API Key 不会自动迁移。升级后请在设置页重新填写一次 API Key,之后会保存到本地加密密钥存储,以避免继续触发钥匙串访问授权弹窗。

## 发布资产

- `SnapAI-v1.6.9.zip`
- `snapai-manifest-v1.6.9.json`
- `snapai-manifest-v1.6.9.json.sig`
