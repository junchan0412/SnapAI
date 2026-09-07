# 模块边界

SnapAI 由 SwiftPM 管理三个生产 target。共享逻辑只有 `Sources/SnapAILogic` 中的一份定义；App 不再通过 symlink 或同名副本重新编译核心模型和服务。

| Target | 职责 | 依赖 |
| --- | --- | --- |
| `SnapAILogic` | 配置与模型、请求路由、SSE 解码、历史存储、隐私处理、系统取词与诊断 | Foundation、Combine，以及所需的 macOS 系统框架 |
| `SnapAI` | SwiftUI 界面、窗口、菜单、用户操作与 App 生命周期 | `SnapAILogic` |
| `SnapAIUpdater` | 更新安装进程 | 独立可执行程序 |

`SnapAILogic` 可以使用 AppKit、Carbon 等系统 API，但不包含 SwiftUI 界面、窗口控制器或文档面板。它不能导入自身。

## 访问级别

共享实现默认使用 Swift 5.9 的 `package`。同一 package 内的 App 和测试可以消费这些声明，其他 package 不能因此访问它们。原有 `public` API 保留；`private`、`fileprivate` 和受限 setter 继续限制实现细节。

新增共享类型或成员时，应按实际调用边界选择访问级别，不应为了让 App 编译而使用 `@testable import`，也不应批量扩大为 `public`。App 文件直接 `import SnapAILogic`，使用同一个 `AIAction`、`AppSettings`、`HistoryEntry` 等类型。

Swift 不会把 struct 隐式 memberwise initializer 自动提升为 `package`。App 确实需要构造实例时，应提供显式 `package init`。默认值放在 initializer 参数中，保留原有值和调用方式，并避免 UUID、日期等默认表达式重复求值。仅供模块内部使用的构造器不需要扩大权限。

## 单一实现

本次统一将剩余 37 份 symlink 改为真实库源码，并删除 App 中对应的源码。当前逻辑模块共有 84 个真实 Swift 文件。

旧 `AutomationURLCommandAppBridge.swift` 中重复的 5 个 Automation 类型和 `AIAction` 扩展已删除。URL 命令处理直接使用逻辑模块返回的值；不再把同一种枚举转成 raw value 后重新构造，也不再复制同一种历史筛选结构。

保留下来的 App bridge 用来连接界面操作、系统反馈或不同职责的参数类型。不能再为同一个核心类型维护第二份实现。

## 构建与验证

先载入项目提供的 toolchain 配置，避免部分 Command Line Tools 缺少 SwiftUI 宏插件的问题：

```sh
source scripts/configure-swift-toolchain.sh
swift build --product SnapAI
swift build --product SnapAIUpdater
scripts/check-logic-symlinks.sh
scripts/run-logic-tests.sh
scripts/run-streaming-runtime-tests.sh
scripts/run-app-runtime-tests.sh
```

边界检查脚本与 manifest 保留历史文件名，以兼容 CI 和发布入口。现在检查的是：所有共享源码都是实际文件、manifest 与源码一致、App 没有重复核心源码或同名顶层类型、逻辑模块没有 UI 或自身依赖，以及生产代码不通过 `@testable` 绕过访问限制。

运行时测试先单独编译并链接一次 `SnapAILogic`，然后编译 App 协调器与测试代码。两侧必须使用相同的 `-package-name`；当前脚本统一使用 `snapai`。不能混用另一个 package identity 生成的 `.swiftmodule`。

测试使用独立配置 suite，并通过 `SNAPAI_LOGIC_TESTS=1` 隔离历史、凭据与路由指标目录。流式与 App 运行时测试使用本地 fixture，不依赖真实模型服务。
