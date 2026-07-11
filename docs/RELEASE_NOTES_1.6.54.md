# SnapAI 1.6.54

SnapAI 1.6.54 继续治理 app/logic 重复编译边界。本版把写回状态、撤销判断、恢复建议和失败诊断从 AppKit 执行器中拆出,形成可独立测试的纯 logic source of truth。

## 重构

- 新增 `TextWriteBackLogic`,统一 `TextWriteBackOperation`、目标状态快照、撤销状态、记录状态、失败诊断、追加 payload 和粘贴准备时序。
- `TextEditTransaction` 从 410 行缩减为 145 行 app-only adapter,只保留 `NSRunningApplication` 激活、AX 选区恢复、粘贴和剪贴板恢复。
- `WriteBackCompatibility` 从 symlink 迁移为 `SnapAILogic` 真实源码,并删除 app target 中的重复源码。
- `WriteBackCommand` 直接复用 `TextWriteBackOperation`,删除 `WriteBackCommandOperation` 及 app bridge 中的枚举转换。
- logic tests 改用目标状态 snapshot,不再构造 AppKit 写回记录或依赖运行应用对象。

## 性能与内存

- app target 不再重复编译写回兼容规则和 300 余行纯状态/诊断逻辑。
- 写回记录通过轻量值类型快照进入 logic 层,避免核心状态长期持有 AppKit 对象。
- 统一 operation 类型,减少执行链上的中间映射和分支维护成本。

## 边界基线

- `SnapAILogic` symlink:37 个,由 39 个下降 2 个。
- `SnapAILogic` 真实源码:39 个,由 37 个增加 2 个。
- remediation gate 禁止 `TextEditTransaction` 进入 logic target,并禁止 `WriteBackCompatibility` / `TextWriteBackLogic` 回退为 symlink 或 app 重复源码。

## 验证

- `scripts/run-audit-remediation-check.sh`
- `scripts/run-logic-tests.sh`
- `swift build`
- `scripts/run-macos-smoke-tests.sh --skip-logic`
- `scripts/preflight-release.sh`

## Release 资产

- `SnapAI-v1.6.54.zip`
- `snapai-manifest-v1.6.54.json`
- `snapai-manifest-v1.6.54.json.sig`
- `snapai-sbom-v1.6.54.json`
