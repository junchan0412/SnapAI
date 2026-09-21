# SnapAI 1.6.4

SnapAI 1.6.4 是一次文档与工程边界收口版本,确保公开 README 使用当前设置界面截图,并补齐写回协调层的命名入口。

## 主要更新

- README 设置页截图更新为当前 sidebar/detail 设置界面。
- 文档截图已替换本机配置名和端点片段,更适合公开发布页展示。
- 新增 `WriteBackCoordinator` 边界类型,并保留 `ResultWriteBackCoordinator` 兼容别名。
- 继续沿用固定自签名证书、签名 manifest、zip SHA256、bundle id 与 designated requirement 校验。

## 验证

- `./scripts/run-logic-tests.sh`
- `swift build`
- `scripts/preflight-release.sh`

