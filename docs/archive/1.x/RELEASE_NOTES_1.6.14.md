# SnapAI 1.6.14

SnapAI 1.6.14 继续完成审计报告中“设置页职责过宽”的收口。本版把通用设置和权限设置拆出主设置视图,并移除不再使用的旧 layout helper。

## 改进

- 新增 `GeneralSettingsSection`,集中承载工作模式、启动与显示、取词、上下文包、隐私、iCloud 同步、打字机动画和配置迁移入口。
- 新增 `PermissionSettingsSection`,集中承载辅助功能权限状态、系统设置跳转和重新检测。
- `SettingsView` 进一步收敛为窗口导航、标题栏、置顶按钮和 section 组合层。
- 删除已无调用的 `SettingsViewLayout.swift`,避免旧 helper 与新 section 局部 helper 并存造成维护误读。

## 发布资产

- `SnapAI-v1.6.14.zip`
- `snapai-manifest-v1.6.14.json`
- `snapai-manifest-v1.6.14.json.sig`
