# SnapAI 1.6.16

SnapAI 1.6.16 继续补强审计报告指出的系统级测试缺口。本版新增 app bundle 启动 smoke,让 release preflight 在签名后确认构建出的 `SnapAI.app` 可以被 macOS 正常打开。

## 改进

- 新增 `scripts/run-app-launch-smoke.sh`,通过 LaunchServices 打开指定 app bundle,检测新进程,并在验证后终止本次新进程。
- `scripts/preflight-release.sh` 在签名和版本校验后执行 app bundle 启动 smoke。
- README 更新本机 smoke 范围,明确 release preflight 已覆盖启动级校验。

## 发布资产

- `SnapAI-v1.6.16.zip`
- `snapai-manifest-v1.6.16.json`
- `snapai-manifest-v1.6.16.json.sig`
