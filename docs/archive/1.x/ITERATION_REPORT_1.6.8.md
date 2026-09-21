# SnapAI 1.6.8 迭代报告

## 背景

本轮来自两类实际使用问题:

1. 默认动作只有提问和翻译具备默认快捷键,润色、总结和解释代码需要用户手动配置,不符合“开箱即用”的菜单栏工具预期。
2. 部分应用中明明选中了文本,执行动作时仍提示未检测到选中文本;同时旧版写回在 AX 选区不可见时会按原文字符数发送 `Shift + Left`,在复杂编辑器中可能导致结果追加到错误位置。

## 目标

- 补齐默认动作快捷键。
- 提供一键恢复默认快捷键入口。
- 扩大 AX 取词覆盖面。
- 提升剪贴板复制兜底成功率。
- 移除高风险的字符数重选写回策略。
- 重写 README,让用户快速理解安装、权限、快捷键、更新和故障排查。

## 实现摘要

### 默认快捷键

- `AIAction` 新增默认动作名称和默认快捷键映射。
- 默认动作现在分别绑定 `Option + A/T/P/S/E`。
- `AppSettings.restoreDefaultHotKeys()` 负责恢复默认动作和快捷提问面板快捷键。
- 恢复逻辑会保留用户自定义动作,但会清理占用默认组合的自定义动作快捷键,避免恢复后立即产生冲突。
- 设置页动作工具栏新增“恢复默认快捷键”按钮。

### 取词

- AX 遍历预算从较浅的 focused/window 检查扩大到更深的目标应用树。
- 遍历新增 `AXMainWindow`、`AXWindows`、`AXSelectedChildren`、`AXSelectedRows` 和 `AXSelectedColumns` 等常见入口。
- 新增基于 `AXStringForRange` 的参数化 range 文本读取。
- 通过访问计数和节点 hash 避免复杂 AX 树重复遍历。
- 剪贴板复制兜底从单次 `Command + C` 升级为最多 3 次重试。
- 剪贴板读取复用 `ServicePasteboardText`,支持更多文本类型。

### 写回

- `TextEditTransaction` 新增 `assumeSelectionIsPreserved`。
- AX 可见选区存在时直接粘贴。
- 有 AX snapshot 时先恢复选区再粘贴。
- 剪贴板和 Services 捕获时信任目标应用保留原选区,直接粘贴。
- 删除旧版 `sendShiftLeftArrow` 和字符数重选延迟路径。

## 验证

- `scripts/run-logic-tests.sh` 通过。
- `swift build` 通过。
- 构建过程中仍有本机 Command Line Tools 搜索路径 warning,但不影响本轮编译结果。

## 剩余风险

- 不同应用对 AX 和剪贴板的支持差异很大,真实兼容性仍需要持续建立应用矩阵。
- 对极端自绘编辑器、远程桌面、虚拟机、网页 canvas 编辑器等场景,仍可能只能使用快捷提问或手动复制。
- 自动写回依赖目标应用保留选区;若目标应用在失焦时主动丢弃选区,SnapAI 会尽量避免错误重选,但仍可能需要用户手动粘贴。

## 后续建议

- 建立“应用兼容性中心”,记录每个目标应用最近的取词/写回成功率。
- 对高风险应用默认只复制结果或要求二次确认。
- 为写回增加轻量 post-check,检测粘贴后是否可能变成追加。
- 增加人工 UI smoke test 清单,覆盖 Safari、Chrome、TextEdit、Notes、Pages、VS Code、Cursor、Obsidian、Notion、微信/飞书等常见应用。
