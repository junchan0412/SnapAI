# SnapAI 1.6.34

SnapAI 1.6.34 继续加固 `SnapAILogic` target 边界。本版禁止进入 logic target 的源码 `import SnapAILogic`,避免仍通过 symlink 镜像的 app 源文件形成 target 自导入。

## 改进

- `scripts/check-logic-symlinks.sh` 将 `SnapAILogic` 纳入 forbidden imports。
- 迁移计划补充自导入防护说明。
- README 更新到 1.6.34。

## 验证

- `scripts/check-logic-symlinks.sh`
- `scripts/run-audit-remediation-check.sh`
- `scripts/run-logic-tests.sh`
- `swift build`
- `scripts/preflight-release.sh`

## Release 资产

- `SnapAI-v1.6.34.zip`
- `snapai-manifest-v1.6.34.json`
- `snapai-manifest-v1.6.34.json.sig`
- `snapai-sbom-v1.6.34.json`
