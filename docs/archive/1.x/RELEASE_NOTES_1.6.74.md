# SnapAI 1.6.74

SnapAI 1.6.74 是一次面向现代 macOS 原生质感与系统级视觉体验的 UI/UX 全面重构版本。

## UI 与 UX 重构

- **全局设计令牌升级（`SnapAIUI`）**：面板圆角增大至 14pt、卡片圆角 10pt、控件圆角 8pt，全界面采用 Apple 风格的连续曲率；间距阶与边距扩展至 16pt，消除视觉拥挤。
- **排版系统规范化（Typography）**：引入统一的字体层级令牌（`panelTitle` / `sectionLabel` / `bodyText` / `metaText`），替代各视图中零散硬编码的字体定义。
- **微交互与动效反馈**：`SnapAIIconButtonStyle` 支持动态悬停（hover）高亮与按压缩放反馈；`SnapAIPrimaryButtonStyle` 增加触控级弹性交互。
- **结果面板与追问体验**：标题字阶、动作切换胶囊、原文编辑器、错误重试与追问输入框全部收敛至设计令牌。
- **设置与历史中心重塑**：设置窗口最小宽度优化至 780pt；全部设置 Section 与历史记录列表、卡片、空态均统一为自适应设计令牌驱动。

## 验证

- `scripts/run-audit-remediation-check.sh`
- `scripts/run-logic-tests.sh`
- `./build.sh`
- release preflight、签名、manifest、SBOM 与 zip 校验

本版本没有改变 provider 协议、隐私策略、历史数据格式或自动更新验证协议。
