# SnapAI 1.6.11

SnapAI 1.6.11 继续按审计报告补强发布前验证。1.6.9 已新增 macOS smoke 脚本,本版把它正式接入 release preflight,让每次发包前都能覆盖基础系统交互探测。

## 改进

- `scripts/preflight-release.sh` 新增 macOS smoke 测试步骤。
- `scripts/run-macos-smoke-tests.sh` 新增 `--skip-logic` 参数,release gate 中可复用剪贴板和权限探测而不重复跑完整逻辑测试。
- release preflight 现在覆盖逻辑 target 边界、逻辑测试、macOS 剪贴板 roundtrip/restore、辅助功能探测、屏幕录制探测、SwiftPM build、正式签名、manifest 签名和 release zip 解包验证。

## 发布资产

- `SnapAI-v1.6.11.zip`
- `snapai-manifest-v1.6.11.json`
- `snapai-manifest-v1.6.11.json.sig`
