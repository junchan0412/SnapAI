# SnapAI 1.6.19 迭代报告

## 背景

1.6.18 已生成 SBOM,但审计报告中“SBOM/漏洞扫描纳入发布门禁”的漏洞扫描部分仍未形成约束。当前项目没有外部 SwiftPM 依赖,因此最合适的策略是把“无依赖”变成可验证事实,并在未来新增依赖时要求真实扫描器。

## 本轮目标

- 增加供应链扫描脚本。
- 接入 CI 和 release preflight。
- 避免在缺少扫描器时对未来新增依赖静默放行。

## 实现摘要

- 新增 `scripts/run-supply-chain-scan.sh`。
- 脚本读取 `swift package show-dependencies --format json`。
- 依赖数为 0 时通过;依赖数大于 0 时优先运行 `osv-scanner`,否则失败。
- 更新 `.github/workflows/ci.yml` 和 `scripts/preflight-release.sh`。

## 验证

- `scripts/run-supply-chain-scan.sh`
- 后续 release preflight 会继续覆盖供应链扫描、逻辑测试、macOS smoke、app launch smoke、release build、签名、manifest 签名、SBOM 和 zip 校验。

## 剩余风险

当前门禁覆盖 SwiftPM 依赖层。若未来引入 Homebrew、npm、Python、vendored 二进制或 Sparkle 等外部组件,还需要把对应 lockfile 或二进制扫描纳入同一门禁。
