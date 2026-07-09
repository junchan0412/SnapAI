# SnapAI 1.6.9 迭代报告

## 背景

本轮按 `audit-report-SnapAI-2026-07-08.html` 推进第一批审计修复。报告指出 7 个问题:Keychain 写入失败可见性、设置域职责过宽、缺少真实 macOS smoke、CI action pinning、SnapAILogic symlink 边界、AI prompt/privacy/fallback eval 缺口、release unsafe flags。

## 本轮闭环

- Keychain 风险:改为 `LocalSecretStore`,API Key 使用 AES.GCM 本地加密存储,保存失败会进入诊断状态。
- 设置域职责:拆分 `SettingsTypes`,AppSettings 的 context/history/work mode extension,以及隐私、上下文包、配置迁移设置组件。
- macOS smoke:新增 `scripts/run-macos-smoke-tests.sh`,覆盖边界校验、逻辑测试、剪贴板 roundtrip/restore、辅助功能和屏幕录制探测。
- CI pinning:`actions/checkout` pin 到 commit SHA。
- SnapAILogic 边界:新增 `scripts/logic-symlink-manifest.txt` 和 `scripts/check-logic-symlinks.sh`,并接入 CI 与 preflight。
- AI eval:新增 prompt/privacy/fallback 语料测试,覆盖高风险 secret、prompt injection、本地优先和不安全云端 fallback 跳过。
- Release flags:移除 `unsafeFlags(["-O"])`,保留标准 `swift build -c release` 验证。

## 验证

- `scripts/check-logic-symlinks.sh` 通过。
- `scripts/run-logic-tests.sh` 通过。
- `swift build` 通过。

本机 Command Line Tools 仍会输出 framework search path warning,但构建和测试均成功。

## 剩余工作

报告中的中长期方向尚未全部完成:SettingsView 仍偏大,完整 UI automation / screenshot / hotkey E2E 仍需要持续建设,`Sources/SnapAILogic` 仍是 symlink 镜像而非真实 library target。后续小版本应继续拆分 Provider/Action/History UI,并逐步把纯逻辑文件迁移到真实 library target。
