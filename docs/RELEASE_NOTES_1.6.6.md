# SnapAI 1.6.6

SnapAI 1.6.6 是 1.6.5 的发布门禁修正版,重点修复 GitHub Actions Xcode 环境下更严格的 Swift 编译检查,让标准测试目标、CI 和 release 资产重新保持一致。

## 主要更新

- 修复命令面板动作排序在 CI Swift 工具链中的类型推断失败。
- 修复文本捕获完成回调跨线程捕获可变结果导致的 Swift 并发检查失败。
- 修复结果面板打字机计时器回调中的 `self` 捕获方式。
- 修复快捷提问截图完成回调中的弱引用与结果捕获预警。
- 修复标准 `swift test` 与本机 `swiftc` 兼容 runner 对测试入口的不同要求。
- 保留 1.6.5 新增的 `SnapAILogic` library target、`SnapAILogicTests` test target 和 GitHub Actions CI。
- 继续使用固定自签名证书、签名 manifest、zip SHA256 和 designated requirement 校验链路。

## 验证

- `git diff --check`
- `scripts/run-logic-tests.sh`
- `swift build`
- `SNAPAI_MANIFEST_PRIVATE_KEY="$HOME/.snapai/snapai-manifest-private.pem" scripts/preflight-release.sh`
