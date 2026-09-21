# SnapAI 1.6.20 迭代报告

## 背景

审计报告指出当前逻辑测试无法覆盖真实 macOS 全局快捷键注册。1.6.16 已加入 app launch smoke,但热键仍停留在逻辑层冲突检测和注册协调测试。

## 本轮目标

- 增加真实系统热键注册探测。
- 不占用用户常用快捷键。
- 在验证结束后立即释放注册。

## 实现摘要

- 更新 `scripts/run-macos-smoke-tests.sh`。
- 临时调用 `RegisterEventHotKey(kVK_F19, cmdKey | optionKey | shiftKey, ...)`。
- 注册成功后立即 `UnregisterEventHotKey`。
- 注册失败时输出 `failed(status)` 并让 smoke 失败。

## 验证

- `scripts/run-macos-smoke-tests.sh --skip-logic`
- 后续 release preflight 会继续覆盖供应链扫描、逻辑测试、macOS smoke、热键注册探测、app launch smoke、release build、签名、manifest 签名、SBOM 和 zip 校验。

## 剩余风险

这验证了系统级热键注册能力,但还没有模拟真实快捷键事件触发 SnapAI 动作。后续可以增加 helper harness,注册热键后发送 CGEvent 并断言 handler 被调用。
