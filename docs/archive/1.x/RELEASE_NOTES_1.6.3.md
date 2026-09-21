# SnapAI 1.6.3

SnapAI 1.6.3 是一次历史知识库与发布稳定性补丁版本,重点补齐本地语义搜索,并让历史窗口、历史导出 URL 和“从历史创建上下文包”使用一致的搜索结果。

## 修复与优化

- 历史搜索新增本地语义匹配,不依赖云端 embedding,不会把历史内容发送给外部服务。
- “钥匙串重复授权”等中文查询可以命中 Keychain、codesign、自签名证书相关历史;“首 token 备用模型”等查询可以命中路由、fallback、供应商表现相关历史。
- 历史窗口搜索占位文案同步提示语义搜索能力。
- URL 自动化中的历史导出和历史上下文包创建改为复用同一条搜索管线,与历史窗口结果保持一致。
- README 和 UI 总览图同步到 1.6.3。

## 更新安全

- 正式 release 构建继续要求稳定自签名证书,不会回退到 ad-hoc 签名。
- 应用内更新继续要求下载并验证 `snapai-manifest-vX.X.X.json` 与 `snapai-manifest-vX.X.X.json.sig`。
- Manifest 内记录 bundle id、designated requirement、证书指纹和 zip SHA256;应用先验签 manifest,再信任其中的更新包校验信息。

## 验证

- `./scripts/run-logic-tests.sh`
- `swift build`
- `scripts/preflight-release.sh`
- `plutil -lint Resources/Info.plist`
- `git diff --check`

