# SnapAI 1.6.11 迭代报告

## 背景

审计报告指出项目缺少真实 macOS UI/AX/剪贴板/快捷键端到端测试。1.6.9 先补了本地 smoke 脚本,但它还没有进入正式 release gate。

## 本轮目标

- 把 macOS smoke 纳入 release preflight。
- 避免 preflight 中重复跑完整逻辑测试。
- 让每个正式包都经过剪贴板和权限探测。

## 实现摘要

- `scripts/run-macos-smoke-tests.sh` 新增 `--skip-logic`。
- `scripts/preflight-release.sh` 在逻辑测试后执行 `scripts/run-macos-smoke-tests.sh --skip-logic`。
- smoke 仍覆盖 SnapAILogic symlink manifest、剪贴板 roundtrip/restore、Accessibility 状态和 Screen Recording 状态。

## 验证

- 后续 1.6.11 release preflight 会直接验证新 gate。

## 剩余风险

这仍不是完整 UI automation。下一步应增加真实窗口打开、快捷键注册状态、结果面板交互和设置页 snapshot/interaction 测试。
