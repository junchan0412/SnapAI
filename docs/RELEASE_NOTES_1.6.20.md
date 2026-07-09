# SnapAI 1.6.20

SnapAI 1.6.20 继续补强审计报告指出的真实 macOS 系统交互测试缺口。本版在 macOS smoke 中新增全局快捷键注册/注销探测。

## 改进

- `scripts/run-macos-smoke-tests.sh` 新增 Carbon `RegisterEventHotKey` 探测。
- smoke 使用低冲突的 `Command + Option + Shift + F19` 组合注册临时热键,验证后立即注销。
- 如果系统拒绝注册,smoke 会失败并输出 Carbon status code。
- release preflight 自动继承该检查。

## 发布资产

- `SnapAI-v1.6.20.zip`
- `snapai-manifest-v1.6.20.json`
- `snapai-manifest-v1.6.20.json.sig`
- `snapai-sbom-v1.6.20.json`
