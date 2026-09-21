# SnapAI 1.6.19

SnapAI 1.6.19 继续补齐审计报告中的供应链发布门禁。本版新增 SwiftPM 依赖扫描脚本,并接入 CI 与 release preflight。

## 改进

- 新增 `scripts/run-supply-chain-scan.sh`。
- 当前 SwiftPM 依赖树为空时,脚本明确输出 `no external SwiftPM dependencies` 并通过。
- 未来如果新增 SwiftPM 依赖,脚本会优先使用 `osv-scanner`;若没有可用扫描器,preflight/CI 默认失败。
- 本地确实需要临时跳过时,必须显式设置 `SNAPAI_ALLOW_MISSING_VULN_SCANNER=1`。
- `.github/workflows/ci.yml` 新增 Supply Chain Scan 步骤。

## 发布资产

- `SnapAI-v1.6.19.zip`
- `snapai-manifest-v1.6.19.json`
- `snapai-manifest-v1.6.19.json.sig`
- `snapai-sbom-v1.6.19.json`
