# SnapAI 1.6.23 迭代报告

## 背景

审计报告中的多项问题已经通过 1.6.9 到 1.6.22 的小版本逐步修复或补强,但这些修复仍分散在测试、脚本、CI 和文档中。缺少统一 gate 会让后续迭代有机会重新引入旧问题。

## 本轮目标

- 将关键审计修复证据转成可执行检查。
- 把检查接入正式 release preflight。
- 保持检查足够轻量,不替代完整测试,但能快速阻断明显回退。

## 实现摘要

- 新增 `scripts/run-audit-remediation-check.sh`。
- 检查 CI SHA pin、`unsafeFlags`、本地密钥存储、prompt/privacy/fallback eval、结果面板命令一致性测试、hotkey handler dispatch smoke、app launch smoke、供应链扫描、SBOM manifest 校验和设置文件规模。
- 更新 `scripts/preflight-release.sh`,在 diff 空白检查后运行该 gate。

## 验证

- `scripts/run-audit-remediation-check.sh`

后续 release preflight 会继续覆盖供应链扫描、逻辑测试、macOS smoke、热键注册探测、handler dispatch 探测、app launch smoke、release build、签名、manifest 签名、SBOM 和 zip 校验。

## 剩余风险

`SnapAILogic` 的真实 library target 迁移仍是长期架构项。当前 gate 能守住 symlink 清单和 forbidden imports,但不能替代未来的模块拆分与访问级别整理。
