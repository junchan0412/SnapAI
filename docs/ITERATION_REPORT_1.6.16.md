# SnapAI 1.6.16 迭代报告

## 背景

审计报告指出项目缺少真实 macOS UI/AX/剪贴板/快捷键端到端测试。1.6.11 已把剪贴板与权限探测纳入 preflight,但 release 包构建后仍缺少“系统能否实际启动 app bundle”的校验。

## 本轮目标

- 增加稳定的 app bundle 启动 smoke。
- 不引入脆弱的 UI 点击自动化。
- 将启动 smoke 纳入 release preflight。

## 实现摘要

- 新增 `scripts/run-app-launch-smoke.sh`。
- 脚本读取 bundle executable 与 bundle id,记录启动前同路径进程,使用 `open -n -g` 启动 app,确认新进程出现,然后只终止本次启动的新进程。
- `scripts/preflight-release.sh` 在 `codesign` 和 app 版本号校验后运行该 smoke。

## 验证

- `scripts/run-app-launch-smoke.sh SnapAI.app`
- 后续 release preflight 会继续覆盖逻辑测试、macOS smoke、debug build、release app 构建、签名、app launch smoke、manifest 签名和 zip 校验。

## 剩余风险

这不是完整 UI automation。后续可以继续补设置窗口截图/交互、快捷键真实注册探测、结果面板按钮行为和 AX 写回场景测试。
