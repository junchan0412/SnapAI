# SnapAI 1.6.73

SnapAI 1.6.73 是一次面向可访问性、持续交互性能和发布可靠性的维护版本。

## UI 与 UX

- 遵循 macOS Reduced Motion 设置。结果面板淡入淡出、流式进度条和打字光标在减少动态效果时改为静态反馈。
- 流式进度条在正常模式使用 30Hz 更新，保留连续移动感并减少无意义的绘制唤醒。
- 设置页的动作库、配置迁移和权限诊断提示共享可取消的瞬时状态控制。连续点击或连续复制时，旧计时器不会提前清理最新提示。

## 稳定性与并发

- `FloatingPanelPresentation` 统一在 `MainActor` 操作 AppKit 面板，并明确动画 completion 的 actor/sendability 契约。
- 构建前探测 SwiftUI macro 能力。Command Line Tools 缺失 `SwiftUIMacros` 时，脚本会自动寻找可用的完整 Xcode，并给出明确的 `DEVELOPER_DIR` 修复路径。

## 验证

- `scripts/run-audit-remediation-check.sh`
- `scripts/run-logic-tests.sh`
- `DEVELOPER_DIR=... swift build -Xswiftc -warn-concurrency -Xswiftc -strict-concurrency=complete`
- `./build.sh`
- `scripts/run-macos-smoke-tests.sh --skip-logic`
- release preflight、签名、manifest、SBOM 与 zip 校验

本版本没有改变 provider 协议、隐私策略、历史数据格式或自动更新验证协议。
