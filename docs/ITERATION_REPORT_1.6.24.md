# SnapAI 1.6.24 迭代报告

## 背景

审计报告指出 `SnapAILogic` target 通过 symlink 镜像 app 源文件,模块边界脆弱。此前版本已经加上 symlink 清单与 forbidden imports gate,但这仍属于防护,不是根治。

## 本轮目标

- 找到可安全渐进迁移的真实 library target 路径。
- 先迁移低耦合逻辑文件,避免一次性大改访问级别和模块边界。
- 保持 app 构建、逻辑测试和 release preflight 全部可通过。

## 实现摘要

- `SnapAI` app target 新增 `SnapAILogic` dependency。
- `ResultRouteStatusText` 从 app target 移入 `SnapAILogic` 实体源码。
- `TextDiff` 从 app target 移入 `SnapAILogic` 实体源码。
- `DiffPreviewWindow` 与 `ResultView` 显式 `import SnapAILogic`。
- `build.sh` 先编译 `SnapAILogic.swiftmodule` 和 object,再用 `-I` 与 object 链接 app 源码,适配当前直接 `swiftc` 的 release bundle 构建方式。
- `scripts/check-logic-symlinks.sh` 从纯 symlink manifest 检查升级为 source manifest 检查,支持实体文件与剩余 symlink 并存。
- 审计修复 gate 新增迁移防回退断言。

## 验证

- `scripts/check-logic-symlinks.sh`
- `scripts/run-audit-remediation-check.sh`
- `scripts/run-logic-tests.sh`
- `swift build`
- `SNAPAI_MANIFEST_PRIVATE_KEY="$HOME/.snapai/snapai-manifest-private.pem" scripts/preflight-release.sh`

## 剩余风险

当前 `SnapAILogic` 仍有 74 个 symlink。后续应继续优先迁移只被少量 UI 文件消费的纯逻辑类型,再处理设置、路由、历史等高耦合模块。大规模迁移前需要规划 `public`/`package` 访问级别和 app target import 边界。
