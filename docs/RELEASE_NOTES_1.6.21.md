# SnapAI 1.6.21

SnapAI 1.6.21 继续补强审计报告指出的 macOS 系统交互测试缺口。本版将 macOS smoke 从热键注册/注销探测升级为 Carbon hotkey handler dispatch 探测。

## 改进

- `scripts/run-macos-smoke-tests.sh` 继续真实调用 Carbon `RegisterEventHotKey` 注册临时热键。
- 新增 `InstallEventHandler` 安装状态检查,确认 hotkey handler 可被系统接受。
- 新增 `kEventHotKeyPressed` Carbon 事件分发探测,验证 handler 能通过 `GetEventParameter` 解析 `EventHotKeyID`。
- 保留剪贴板 roundtrip、剪贴板恢复、辅助功能权限、屏幕录制权限和 release preflight 集成。

## 说明

本版不使用 CGEvent 合成物理按键作为 release gate。macOS 对合成全局热键触发存在环境差异,容易造成不稳定误报;当前 smoke 覆盖热键注册、handler 安装和 Carbon 事件分发路径。后续若要覆盖真实用户按键到动作执行的端到端链路,应增加独立 helper harness 或 UI automation。

## 发布资产

- `SnapAI-v1.6.21.zip`
- `snapai-manifest-v1.6.21.json`
- `snapai-manifest-v1.6.21.json.sig`
- `snapai-sbom-v1.6.21.json`
