# SnapAI 1.6.57

SnapAI 1.6.57 聚焦自动更新模块边界。原 `UpdateChecker.swift` 同时包含纯验证、网络、AppKit UI、解压和安装器,并通过 symlink 在 app/logic 两个 target 中重复编译。本版把它拆成真实 library core 与 app-only adapter。

## 架构与去重

- `Sources/SnapAILogic/UpdateChecker.swift` 成为 620 行真实源码。
- 新增 479 行 `UpdateCheckerApp`,只负责 GitHub 网络请求、AppKit alert、下载、解压、签名连续性和安装启动。
- 删除 app target 中原 1092 行混合 `UpdateChecker.swift`。
- logic tests 继续使用 `UpdateChecker` API,无需依赖 AppKit adapter。

## 安全逻辑

以下规则现在只保留一份 source of truth:

- 官方数字版本解析与比较。
- Release asset 精确命名和重复资产拒绝。
- GitHub digest、manifest SHA256 和签名元数据验证。
- RSA manifest signature 验证。
- bundle identifier、designated requirement 与证书指纹检查。
- 可信安装日志路径解析。

## 诊断逻辑

- `PermissionHealthSnapshot.make` 改为显式接收 `PermissionInstallLogStatus`。
- app bridge 将真实更新日志状态转换为诊断 DTO。
- logic tests 使用确定性的 `.noRecord` 默认值,不再受进程 UserDefaults 污染。

## 边界基线

- `SnapAILogic` symlink:36 个,由 37 个下降 1 个。
- `SnapAILogic` 真实源码:40 个,由 39 个增加 1 个。
- remediation gate 禁止混合 `Sources/SnapAI/UpdateChecker.swift` 返回,并限制 core/app 两侧文件大小。

## 验证

- `scripts/run-audit-remediation-check.sh`
- `scripts/run-logic-tests.sh`
- `swift build`
- `scripts/run-macos-smoke-tests.sh --skip-logic`
- `scripts/preflight-release.sh`

## Release 资产

- `SnapAI-v1.6.57.zip`
- `snapai-manifest-v1.6.57.json`
- `snapai-manifest-v1.6.57.json.sig`
- `snapai-sbom-v1.6.57.json`
