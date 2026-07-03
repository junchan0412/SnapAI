# SnapAI 1.6.6 迭代报告

1.6.6 聚焦发布质量收敛。1.6.5 已完成标准测试目标、CI 门禁和核心模块拆分,但 GitHub Actions 使用的 Xcode Swift 工具链比本机 Command Line Tools 更严格,暴露出类型推断和并发捕获问题。本轮将这些远端门禁问题修复,避免发布资产与 CI 状态不一致。

## 已完成

- `ActionCommandFactory` 的排序闭包改为显式参数类型,避免 CI Swift 工具链无法推断 tuple 类型。
- `TextCapture.captureDetailed` 在切回 `MainActor` 前先固定不可变捕获值,避免后台可变结果被并发闭包引用。
- `ResultViewModel` 的打字机计时器使用显式弱引用 capture list 进入 `MainActor`。
- `QuickInputController` 的截图完成回调显式捕获结果和窗口列表,消除 Swift 6 并发预警。
- 版本、README、UI 总览图、Release Notes 和 Iteration Report 更新到 1.6.6。

## 验证

- 空白 diff 检查通过。
- 逻辑测试通过。
- SwiftPM 构建通过。
- Release preflight 通过,包含 release app bundle 构建、稳定签名、zip 打包、manifest 签名和 release zip 可安装性验证。

## 发布资产

完整 release 包应包含:

- `SnapAI-v1.6.6.zip`
- `snapai-manifest-v1.6.6.json`
- `snapai-manifest-v1.6.6.json.sig`

