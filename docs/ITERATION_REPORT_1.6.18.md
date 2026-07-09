# SnapAI 1.6.18 迭代报告

## 背景

审计报告指出发布链路虽然已有签名 manifest、zip SHA256、bundle id、designated requirement 和回滚路径,但 SBOM/漏洞扫描尚未纳入发布门禁。项目当前 SwiftPM 没有第三方依赖,因此适合先落地轻量 SBOM,把供应链事实固化到 release 资产中。

## 本轮目标

- 为每个 release 生成 SBOM。
- 让签名 manifest 覆盖 SBOM 文件摘要。
- 在 release preflight 中验证 SBOM 存在且 sha256 一致。

## 实现摘要

- 新增 `scripts/generate-sbom.sh`。
- 更新 `scripts/package-release.sh`,在 zip 后生成 `snapai-sbom-vX.X.X.json`。
- 更新 `scripts/preflight-release.sh`,校验 SBOM asset 和 manifest 摘要。
- README 同步 release 打包说明。

## 验证

- `SNAPAI_MANIFEST_PRIVATE_KEY=... SNAPAI_RELEASE=1 scripts/package-release.sh <version>`
- `python3 -m json.tool dist/snapai-sbom-<version>.json`
- 后续 release preflight 会继续覆盖逻辑测试、macOS smoke、app launch smoke、release build、签名、manifest 签名、SBOM 和 zip 校验。

## 剩余风险

当前 SBOM 已记录 SwiftPM 依赖事实,但还没有接入外部 CVE 数据库扫描。后续可以在本机或 CI 有 `osv-scanner`/`trivy`/`grype` 时增加可选扫描门禁。
