# SnapAI 1.6.18

SnapAI 1.6.18 补强审计报告中提到的发布供应链透明度缺口。本版新增轻量 SBOM 生成与校验,让每个正式 release 都带有可审计的依赖和发布文件摘要。

## 改进

- 新增 `scripts/generate-sbom.sh`,生成 CycloneDX JSON 格式的 `snapai-sbom-vX.X.X.json`。
- SBOM 记录应用版本、Git commit、release zip SHA256、`Package.swift` SHA256、`Resources/Info.plist` SHA256 和 SwiftPM 依赖树。
- `scripts/package-release.sh` 打包时自动生成 SBOM,并把 SBOM asset 的 sha256 写入签名 manifest。
- `scripts/preflight-release.sh` 新增 SBOM 文件存在性和 manifest sha256 一致性校验。

## 发布资产

- `SnapAI-v1.6.18.zip`
- `snapai-manifest-v1.6.18.json`
- `snapai-manifest-v1.6.18.json.sig`
- `snapai-sbom-v1.6.18.json`
