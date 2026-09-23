# SnapAI 2.0.6

SnapAI 2.0.6 是设置窗口 Liquid Glass 收尾版本：侧栏获得真正的 behind-window 毛玻璃（桌面透过来），详情区保持不透明基底，还原 macOS 系统设置的“侧栏透明 + 详情实底”布局；同时删除 2.0.4 重构后残留的死代码与最后一处卡片内结构性分隔线。功能、配置、快捷键与历史记录完全兼容 2.0.x。

## 设置窗口毛玻璃收尾

- 新增 `snapAISidebarGlass()`（`Sources/SnapAI/SnapAILiquidGlass.swift`）——`NSVisualEffectView` 的 `.sidebar` 材质 + `.behindWindow` 混合，桌面透过窗口显现；低版本走系统材质，行为一致。
- 设置窗口透明化（`Sources/SnapAI/WindowCoordinator.swift`）：`fullSizeContentView` + 透明标题栏 + `isMovableByWindowBackground`（透明标题栏下保持可拖拽）+ `isOpaque = false` + clear 背景；详情区由自身的不透明 canvas 兜底。
- 侧栏 `List` 显式透明（`snapAIChrome()`，与历史窗口侧栏列表先例一致），避免不透明列表基底盖住 vibrancy。
- 工作模式卡片内结构性 `Divider` 改留白（2.0.4 分隔线治理的遗漏点）；菜单/行间/双列对照的语义分隔保留不变。

## 死代码清理

- 删除零调用的 `snapAISurface / SnapAISurfaceModifier` 与零引用的 `Surface.chrome`（`Sources/SnapAI/SnapAIUI.swift`）。审计门禁的 legacy 零残留检查现在真正零残留（只剩脚本自身的门禁字符串）。
- 审计门禁新增三条：`snapAISidebarGlass` helper、侧栏用法、窗口透明。

## 视觉验证

- 深色设置页：侧栏毛玻璃透桌面、选中行高亮可读，详情区实底，当前工作模型卡片为悬浮玻璃，无接缝。
- 浅色设置页：侧栏浅色毛玻璃 + 详情实底，回退渲染正常。
- 截图：`docs/screenshots/snapai-settings-glass-dark.png`、`snapai-settings-glass-light.png`（2000×1496，窗口直出）。

## 兼容性

- 最低系统版本保持 macOS 14；behind-window 材质为系统原生，低版本无行为差异。
- 不改变更新包的下载、校验与安装安全链路；manifest 公钥、bundle id、签名连续性校验保持不变。
- 提供 ZIP、签名 manifest、签名文件与 SBOM。应用仍采用自签名分发，尚无 Apple notarization；首次安装步骤见 README。

## 已知事项

- 无。preflight 全绿后发布。
