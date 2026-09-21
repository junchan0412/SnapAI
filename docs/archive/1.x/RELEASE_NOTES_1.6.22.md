# SnapAI 1.6.22

SnapAI 1.6.22 继续补强审计报告指出的测试真实性缺口。本版聚焦结果面板命令、菜单快捷键和命令面板入口的一致性防回归。

## 改进

- 新增结果面板菜单 command id 唯一性测试。
- 新增结果面板菜单 action 唯一性测试。
- 新增结果面板快捷键组合冲突检测测试。
- 新增结果面板可见命令完整性测试,确保可见命令都有正式菜单命令、处于可执行状态,并保留命令面板需要的 id、title 和 keywords。
- 新增 streaming 状态测试,确保生成中只暴露停止命令,隐藏写回和重新生成。

## 发布资产

- `SnapAI-v1.6.22.zip`
- `snapai-manifest-v1.6.22.json`
- `snapai-manifest-v1.6.22.json.sig`
- `snapai-sbom-v1.6.22.json`
