# SnapAI 无障碍走查

2.0.3 补过一轮标签,但从未做过完整的 VoiceOver 走查和纯键盘走查。本文记录
2026-09-28 这一轮:方法、覆盖范围、发现的问题、整改结果,以及仍需人工过一遍的清单。

## 方法

### 名称走查(可自动化)

`scripts/ax-audit.sh` 对每个 surface 起一个隔离预览进程,遍历窗口的
Accessibility 树并报告「可交互但没有可读名称」的控件 —— **VoiceOver 朗读的正是这棵树**,
所以这一步等价于对窗口内容做一次 VoiceOver 名称走查:

```bash
scripts/ax-audit.sh                 # 全部默认 surface
scripts/ax-audit.sh --tree general   # 打印整棵树,定位具体控件
```

判定口径(与 VoiceOver 的读法一致):`Title → Description → Help → Value`
(静态文本正文在 Value)。报告里附带**同一父节点下、位于该控件之前的最近一条静态文本**,
因为 SwiftUI 常把可见标签渲染成兄弟静态文本 —— 这条文本就是该补的
`accessibilityLabel` 文案。

不计入的系统控件:窗口关闭/最小化/缩放按钮、滚动条与步进器的箭头子控件
(名字挂在 `AXScrollBar` / `AXIncrementor` 父元素上,不在本仓库可改范围内)。

### 纯键盘走查

能自动化的部分由既有测试覆盖,剩余部分见文末人工清单。

## 覆盖范围

16 个 surface:设置 6 个 section(模型/供应商/动作/历史设置/通用/权限)、
结果面板、快捷提问、历史窗口、命令面板、欢迎页、权限健康中心、
空供应商设置、空历史、更新窗口、差异预览。

## 第一轮结果与整改

| 阶段 | 无可读名称的交互控件 |
| --- | ---: |
| 初测(未排除系统子控件) | 60 |
| 排除系统子控件后的**真实问题** | 39 |
| 整改后(16 个 surface) | **0** |

整改清单:

| 位置 | 问题 | 修法 |
| --- | --- | --- |
| 模型页 | 「优先偏好」`Picker`、自动路由 / Fallback 两个开关、Temperature 滑杆 | 控件自身补 `accessibilityLabel` |
| 通用页 | 开机启动 / Dock 图标 / 优先辅助功能取词三个开关 | `settingsToggleRow` 统一按 `title` 补名 |
| 通用页 · 隐私 | 发送前预览 / 本地脱敏 / 图片本地 OCR 三个开关 | `toggleRow` 统一按 `title` 补名 |
| 通用页 · 隐私 | 脱敏规则行的启用开关、名称/正则表达式/替换为三个输入框 | 逐项补名,启用开关带上规则名 |
| 通用页 · 隐私 | 规则测试样本 `TextEditor` | 补「规则测试样本」 |
| 通用页 · 上下文包 | 选择器、启用开关、名称输入、内容编辑器、新增输入框 | 逐项补名,带上下文包名 |
| 历史设置 | 保留条数 `Stepper` | 补「保留历史记录条数」 |
| 历史窗口 | 搜索框、标签输入框 | 补名 |
| 命令面板 | 搜索输入框 | 补名 |

规律:问题几乎全部来自「可见标签是兄弟文本、控件自身没带名字」的写法 ——
`Toggle("", ...).labelsHidden()`、`TextField(占位符, ...)`、空 `title` 的 `Picker`。
新写这类控件时直接给修饰符加 `accessibilityLabel`,不要依赖旁边的 `Text`。
带 `.help(...)` 的图标按钮会把 help 文本带进 `AXHelp`,VoiceOver 能读到,已验证。

## 键盘走查:已由自动化覆盖的部分

- 菜单与命令面板的快捷键一致性:`testResultCommandFactoryKeepsMenuShortcutsAndVisibleActionsConsistent`;
- Escape 归属(结果面板失焦 / 快捷提问 / 其他窗口不被误吃):
  `scripts/run-app-runtime-tests.sh` 的 `testEscapeOwnership` 逐条断言;
- 状态栏菜单、主菜单的 `keyEquivalent` 与分组在装配层集中定义
  (`StatusMenuBuilder` / `MainMenuBuilder`),命令面板项由 `ResultCommandFactory` 统一生成;
- 减少动态效果已有代码分支:`accessibilityDisplayShouldReduceMotion`(面板与流式 UI)。

## 仍需人工过一遍(本机无法自动完成)

1. 打开「完整键盘访问」后,Tab / Shift+Tab 在设置页六个 section 内的**遍历顺序**与焦点环可见性;
2. VoiceOver 的**朗读顺序与 rotor**:侧栏行、卡片内多列布局的实际读序是否与视觉一致;
3. **实时播报**:流式结果的逐字输出是否需要节流播报、进度类状态是否用 `AXLiveRegion` 思路处理;
4. 「增加对比度」「减少动态效果」两种系统设置下的实际观感。

以上四条是真正的 VoiceOver/键盘人工走查项,脚本无法替代,建议每次大版本前过一遍。

## 复测

改完界面后重跑,退出码非 0 表示又出现了无可读名称的控件:

```bash
scripts/ax-audit.sh
```

需要辅助功能权限(系统设置 → 隐私与安全性 → 辅助功能)。
CI runner 没有辅助功能权限,因此该脚本只在本机 preflight 里跑,不进 GitHub Actions。
