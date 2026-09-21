# SnapAI 1.6.21 迭代报告

## 背景

1.6.20 已加入真实 Carbon 全局热键注册探测,但仍只能证明系统接受注册和注销,不能证明 SnapAI 的 hotkey handler 分发链路可用。审计报告中关于测试真实性的风险仍需要继续收窄。

## 本轮目标

- 在 macOS smoke 中覆盖 hotkey handler 安装。
- 验证 `kEventHotKeyPressed` 事件能够进入 handler 并被正确解析。
- 保持 release preflight 稳定,避免依赖 macOS 对 synthetic global key event 的环境差异。

## 实现摘要

- 更新 `scripts/run-macos-smoke-tests.sh`。
- 通过 `InstallEventHandler(GetApplicationEventTarget(), ...)` 安装临时 hotkey handler。
- 继续使用 `RegisterEventHotKey(kVK_F19, cmdKey | optionKey | shiftKey, ...)` 做真实注册探测。
- 使用 Carbon `CreateEvent`、`SetEventParameter` 和 `SendEventToEventTarget` 分发 `kEventHotKeyPressed` 事件,断言 handler 收到匹配的 `EventHotKeyID`。
- 输出新增 `Hotkey handler install` 和 `Hotkey handler dispatch probe` 两项结果。

## 验证

- `scripts/run-macos-smoke-tests.sh --skip-logic`

后续 release preflight 会继续覆盖供应链扫描、逻辑测试、macOS smoke、热键注册探测、handler dispatch 探测、app launch smoke、release build、签名、manifest 签名、SBOM 和 zip 校验。

## 剩余风险

当前 smoke 覆盖 Carbon 注册与 handler 分发,但仍不是完整的“用户按下快捷键 -> SnapAI 动作执行”端到端 UI automation。后续建议增加独立 helper app 或受控 UI automation harness,在真实应用进程中触发动作并断言结果面板出现。
