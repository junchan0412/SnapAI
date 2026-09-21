# SnapAI 1.6.23

SnapAI 1.6.23 将审计报告修复成果纳入 release preflight。后续每次正式发版都会先运行审计修复状态 gate,避免已完成的安全、测试和发布卫生改进发生回退。

## 改进

- 新增 `scripts/run-audit-remediation-check.sh`。
- `scripts/preflight-release.sh` 新增“运行审计修复状态检查”步骤。
- gate 会检查 CI checkout 是否 pin 到 commit SHA。
- gate 会阻止 `Package.swift` 重新引入 `unsafeFlags`。
- gate 会确认本地密钥存储、prompt/privacy/fallback eval、结果面板命令一致性测试、macOS hotkey handler dispatch smoke、app launch smoke、供应链扫描、SBOM manifest 校验和设置模块拆分规模仍然存在。

## 发布资产

- `SnapAI-v1.6.23.zip`
- `snapai-manifest-v1.6.23.json`
- `snapai-manifest-v1.6.23.json.sig`
- `snapai-sbom-v1.6.23.json`
