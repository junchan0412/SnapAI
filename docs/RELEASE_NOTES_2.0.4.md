# SnapAI 2.0.4

SnapAI 2.0.4 是 Liquid Glass 视觉重构版本：全界面统一为 macOS 26 Liquid Glass 语言（低版本自动回退），删除全部结构性色块与分隔线，并收紧信息展示（端点只显示 host、诊断复制明确不含密钥）。功能、配置、快捷键与历史记录完全兼容 2.0.x。

## Liquid Glass 一致性

- 新增 `Sources/SnapAI/SnapAILiquidGlass.swift`：全项目唯一的 glass 入口，提供 `snapAIGlassCard / snapAIGlassField / snapAIGlassPill / snapAIChrome / snapAIScrollEdge` 修饰符与 `SnapAIGlassToolbarGroup` 容器。macOS 26+ 走 `.glassEffect`（卡片用 `.regular`、可交互组用 `.interactive()`、徽标用 tinted capsule、滚动用 `.soft` 边缘淡化）；macOS 14/15 回退到既有 Surface 语义色，行为一致。
- 结构性 chrome 全部透明化：设置标题栏、结果/快捷提问 header 与 footer、历史工具栏与列表列、命令面板、更新/引导/对比窗口的标题与 footer 区不再绘制任何背景色块，只留排版，由窗口/浮动面板自身材质提供 backdrop。
- 内容卡片全部走 glass：设置各分组卡片、供应商卡片（含当前供应商的 accent 选中描边保留）、动作卡片、历史行、更新说明卡、onboarding 步骤、健康中心卡片与建议面板。
- 输入框走 glass field：原文编辑器、追问框（焦点描边保留）、快捷提问编辑器（新增 glass 描边容器）、历史/命令面板搜索框；AppKit 快捷提问编辑器的不透明底已删除，改由外层 glass 提供填充。
- 状态徽标走 tinted glass pill：固定模型/Fallback/路由 pills、Fallback 开启绿 pill、复制/导出反馈胶囊。
- 结果 footer 操作行包入 `GlassEffectContainer`，组内玻璃在 26+ 融合为连续液态玻璃。
- 审计门禁锁定：`snapAISurface / Surface.chrome / regularMaterial` 在 `Sources/SnapAI` 中零残留（`SnapAIUI.swift` 的 token 定义与 glass 回退分支除外）。

## 分隔线治理

- 删除全部结构性 Divider：窗口 header/content/footer 之间、HSplitView 列之间、卡片内部的分段线，改由留白表达（`compactDivider` helper 改为空留白）。
- 保留语义分隔：菜单内部分组线、模型列表行间线、diff 双列对照线、筛选 popover 的按钮组分隔线。

## 信息密度处理

- 供应商端点只显示 host：新增 `AIProvider.displayHost`（`Sources/SnapAILogic/Provider.swift`），当前工作模型副标题 `肖恩 · https://api.supxh.xin` 改为 `肖恩 · api.supxh.xin`；解析失败/为空回退“未设置端点”。新增 `testProviderDisplayHostShowsOnlyHost` 回归测试。
- API Key 健康只显示计数摘要（`1/1 个供应商已配置`），诊断文本不含 Key 明文/掩码；权限健康中心复制诊断按钮文案改为“完整/精简诊断已复制（不含密钥）”，并在代码注释中锁定该保证。

## 视觉验证

- 深色设置页：当前工作模型卡与供应商卡为悬浮玻璃，header/footer 与窗口基底融合，无接缝。
- 深色结果浮窗：原文为 glass field，footer 操作组融合，追问框 glass 化。
- 深色历史双栏：搜索框 glass field，列表列透明，选中行玻璃高亮。
- 深色命令面板、快捷提问、权限健康中心、动作页均已截图验证；浅色设置页回退渲染正常。

## 兼容性

- 最低系统版本保持 macOS 14；Liquid Glass 仅在 macOS 26+ 生效，低版本为像素级回退，无行为差异。
- 不改变更新包的下载、校验与安装安全链路；manifest 公钥、bundle id、签名连续性校验保持不变。
- 提供 ZIP、签名 manifest、签名文件与 SBOM。应用仍采用自签名分发，尚无 Apple notarization；首次安装步骤见 README。

## 已知事项

- App runtime smoke 中“结果详情按钮无障碍树”两项失败在基线（v2.0.3 未改动树）同样复现，为预存环境问题，非本次回归；其余门禁全绿。
