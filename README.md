# SnapAI

SnapAI 是一个 macOS 菜单栏 AI 工具。你可以在任意应用里选中文字,一键提问、翻译、润色、总结或解释代码;也可以直接打开快捷提问面板输入问题。

![SnapAI 1.6.6 UI 总览](docs/snapai-ui-overview.svg)

![SnapAI 设置界面](docs/snapai-settings.png)

## 1.6.6 版本重点

- 修复 GitHub Actions Xcode 环境下更严格的 Swift 类型推断与并发捕获检查,恢复远端 CI 门禁。
- 命令面板动作排序显式标注排序闭包类型,避免不同 Swift 工具链推断不一致。
- 文本捕获、快捷提问截图回调和结果面板打字机计时器改为稳定捕获不可变值或弱引用,降低 Swift 并发检查风险。
- 继续沿用 1.6.5 的标准 `SnapAILogic` 测试目标、GitHub Actions CI、模块拆分、稳定自签名 release、签名 manifest 和 zip SHA256 校验链路。

## 1.6.5 版本重点

- 新增 `SnapAILogic` SwiftPM library target 和 `SnapAILogicTests` test target,让核心逻辑可以被 `swift test`、IDE 和 CI 标准发现。
- `scripts/run-logic-tests.sh` 保留为兼容包装:有 XCTest 的环境走 `swift test`,仅有 Command Line Tools 且缺 XCTest 的环境自动回退到本机 `swiftc` runner。
- 新增 GitHub Actions CI 门禁,覆盖空白 diff 检查、SwiftPM 构建、标准测试和兼容测试脚本。
- 拆分 `AppDelegate`、`AIRequestRouter`、`Settings` 与 `SettingsView` 的核心边界,新增自动化命令、Services 捕获、写回、路由诊断和设置持久化等独立文件。
- 继续沿用稳定自签名 release、签名 manifest、zip SHA256、bundle id 和 designated requirement 校验链路。

## 1.6.4 版本重点

- 更新 README 设置页示例图为当前 sidebar/detail 设置界面,并移除本机配置名等不适合公开文档的内容。
- 补齐 `WriteBackCoordinator` 边界命名,保留 `ResultWriteBackCoordinator` 兼容别名,让写回协调层更容易被审查和维护。
- 继续沿用 1.6.3 的稳定自签名 release、签名 manifest、zip SHA256、bundle id 和 designated requirement 校验链路。

## 1.6.3 版本重点

- 深度优化“任意应用选中文字 -> SnapAI 理解上下文 -> 执行动作 -> 安全写回”的主链路。
- 继续修复部分应用通过右键 Services 触发动作时偶发“未检测到选中文本”的问题:Services pasteboard 没给出文本时,SnapAI 会保留服务调用瞬间的目标应用,并在剪贴板兜底前主动收起右键菜单等临时 UI。
- 文本捕获新增结构化结果,可区分 Accessibility 直读、剪贴板兜底、剪贴板保护、复制超时和空内容等状态。
- macOS 服务菜单取词更稳,会优先读取系统传入的 Services pasteboard,并兼容 UTF-8/UTF-16、RTF/HTML 与部分旧式 pasteboard 文本类型。
- 权限健康中心和请求诊断会显示捕获方式、失败原因、剪贴板保护原因和等待次数,排查跨应用取词问题更直接。
- 选区来源上下文会把前台应用归类为浏览器、代码编辑器、终端、文档、聊天、邮件或 PDF 阅读器,并以粗粒度提示帮助 AI 理解语境。
- 来源上下文不会把窗口标题、文件路径或具体应用名发送给 AI;诊断中的应用名也会经过敏感信息清洗。
- 自动路由失败时会区分隐藏 thinking 与用户可见输出:只有已经出现可见 partial output 时才阻止静默切换备用模型。
- 设置保存不再无差别重写整份历史 SQLite,减少编辑设置时的无谓 I/O。
- 逻辑测试从单个巨型入口拆分为更新器、写回/捕获、路由、隐私、命令、设置迁移和历史等领域文件,后续定位回归更快。
- 保留 1.5.0 的项目记忆、历史知识库、命令面板主入口和动作模板库;历史搜索新增本地语义匹配,例如“钥匙串重复授权”可命中 Keychain/codesign 相关记录。
- 历史窗口、历史导出 URL 和“从历史创建上下文包”现在共用同一条搜索管线,FTS、筛选与本地语义匹配结果保持一致。

详细发布说明见 [SnapAI 1.6.6 Release Notes](docs/RELEASE_NOTES_1.6.6.md),阶段性复盘和全量审查见 [SnapAI 1.6.6 Iteration Report](docs/ITERATION_REPORT_1.6.6.md)。

## 快速安装

系统要求:macOS 14 或更高版本。

1. 打开 [GitHub Releases](https://github.com/junchan0412/SnapAI/releases),下载最新的 `SnapAI-vX.X.X.zip`。
2. 解压后,把 `SnapAI.app` 移动到 `/Applications` 或 `~/Applications`。建议先移动到固定位置,再授权辅助功能权限。
3. 如果 macOS 提示“已损坏”“无法打开”或“来自未认证开发者”,在终端执行:

```bash
xattr -cr /Applications/SnapAI.app
open /Applications/SnapAI.app
```

如果你放在用户应用目录:

```bash
xattr -cr ~/Applications/SnapAI.app
open ~/Applications/SnapAI.app
```

4. 首次启动后,到系统设置授予辅助功能权限:

```text
系统设置 -> 隐私与安全性 -> 辅助功能 -> 勾选 SnapAI
```

5. 点击菜单栏里的 SnapAI 图标,进入设置页填写 AI 供应商、API Key 和模型。

## 为什么需要 `xattr -cr`

当前 SnapAI 没有使用 Apple Developer ID 公证发布。通过浏览器从 GitHub 下载后,macOS 会给压缩包或应用添加 quarantine 隔离属性。未公证应用在隔离状态下可能会被 Gatekeeper 拦截,表现为无法打开、提示损坏,或需要额外确认。

`xattr -cr /Applications/SnapAI.app` 会递归清除应用 bundle 上的扩展属性,包括 quarantine。应用第一次启动前还没有机会自己处理这个属性,所以首次手动安装时需要用户执行一次。

这一步不会替代辅助功能授权。SnapAI 读取选中文字、模拟复制和粘贴仍然需要你在系统设置中授予辅助功能权限。

## 使用方式

默认快捷键:

| 功能 | 快捷键 |
|------|--------|
| 提问选中文字 | `Option + A` |
| 翻译选中文字 | `Option + T` |
| 快捷提问面板 | `Option + Space` |

基本流程:

1. 在任意应用中选中文字。
2. 按 `Option + A` 提问,或按 `Option + T` 翻译。
3. 在浮动结果窗中复制结果、替换原文、追加到文档,或继续追问。
4. 不想先选中文字时,按 `Option + Space` 打开快捷提问面板。

所有动作、快捷键、Prompt、模型和供应商都可以在设置里自定义。

## 选中文字主链路

SnapAI 1.6.3 对跨应用选中文字工作流做了更细的保护和诊断:

1. 触发动作时,先记录当前前台应用作为可信写回目标。
2. 优先通过 Accessibility API 读取选中文字,成功时不会污染剪贴板。
3. 如果目标应用不支持 Accessibility 直读,会临时模拟 `Command + C` 走剪贴板兜底。
4. 兜底前会完整快照用户剪贴板;如果剪贴板内容过大或格式过多,会取消自动复制,避免破坏用户剪贴板。
5. 捕获成功后,会把选区来源归类为浏览器、代码编辑器、终端、文档、聊天、邮件或 PDF 阅读器,作为粗粒度上下文提示。
6. 请求会合并当前上下文包、动作 Prompt、隐私脱敏结果、图片输入状态和 AI 路由策略。
7. 替换或追加时会再次激活原应用,写回前保护剪贴板,失败时复制结果并给出可复制诊断。
8. 权限健康中心可查看最近一次文本捕获、写回、AI 请求、签名、热键和更新状态。

## 动作模板库

设置页的“动作”区域提供内置动作模板和动作库导入/导出:

- “添加”菜单可快速创建邮件回复、会议纪要、代码审查、中英双语润色、图片理解等常用动作。
- “导出动作库”会把当前动作保存为 JSON,适合备份、迁移或分享给其他用户。
- “导入动作库”支持导入 SnapAI 导出的 JSON 动作包,也兼容旧版纯动作数组 JSON。
- 为避免冲突和泄漏本机配置,导入/导出动作库时会清除全局快捷键、供应商绑定和模型覆盖;API Key 本身从不写入动作库。
- 在 `Command + K` 命令面板里搜索“模板”“动作库”或模板名称,可以直接安装内置动作模板。

## macOS 服务菜单

安装后,支持 Services 的 macOS 应用可以从系统服务菜单把选中文本发送给 SnapAI。常见入口通常在:

```text
应用菜单 -> 服务 -> 用 SnapAI 提问 / 用 SnapAI 翻译 / 用 SnapAI 润色
```

不同应用对 Services 的支持程度不同。如果菜单中暂时没有显示 SnapAI,请确认应用已经移动到固定位置并重新打开 SnapAI;必要时注销或重启一次 macOS 以刷新系统服务索引。

SnapAI 会读取系统服务菜单传入的纯文本、UTF-16 文本、RTF、HTML 和部分旧式 pasteboard 文本类型。若某个应用没有把选区放入 Services pasteboard,SnapAI 会回退到 Accessibility/剪贴板取词路径。SnapAI 会优先复用服务调用瞬间的目标应用,并在复制前收起右键菜单等临时 UI,减少菜单抢走 `Command + C` 的情况。权限健康中心会记录失败原因和恢复建议。

## 自动化 URL Scheme

SnapAI 支持 `snapai://` URL Scheme,可从 Shortcuts、Raycast、Alfred、脚本或其他应用触发。

常用入口:

| URL | 行为 |
|-----|------|
| `snapai://run?action=润色&text=需要处理的文本` | 直接用指定动作处理文本 |
| `snapai://run/润色?text=需要处理的文本` | 用路径形式指定动作并处理文本 |
| `snapai://ask?text=解释这段内容` | 使用“提问”动作 |
| `snapai://translate?text=hello` | 使用“翻译”动作 |
| `snapai://quick?action=翻译&text=预填内容` | 打开快捷提问面板,预填文本并预选动作 |
| `snapai://quick/翻译?text=预填内容` | 用路径形式预选动作并打开快捷提问面板 |
| `snapai://settings?section=privacy` | 打开设置页的指定区域 |
| `snapai://settings/ai` | 用路径形式打开指定设置区域 |
| `snapai://settings/section/permission` | 用二段式路径打开指定设置区域 |
| `snapai://settings/permission/screen-recording` | 用复合路径别名打开权限设置 |
| `snapai://history` | 打开历史记录窗口 |
| `snapai://history?export=true` | 复制全部历史记录 Markdown |
| `snapai://history/export` | 用路径子命令复制全部历史记录 Markdown |
| `snapai://history?export=true&query=release&favorite=true` | 复制筛选后的历史记录 Markdown |
| `snapai://history/context?tag=项目A` | 从筛选后的历史创建并启用上下文包 |
| `snapai://history/context?tag=项目A&name=项目A上下文` | 用指定名称创建或更新历史上下文包 |
| `snapai://history/context?tag=项目A&limit=5&max_chars=1200` | 控制写入记录数和单段文本长度 |
| `snapai://history?create_context=true&favorite=true` | 从收藏历史创建并启用上下文包 |
| `snapai://history?clear=true` | 清空历史记录 |
| `snapai://history/clear` | 用路径子命令清空历史记录 |
| `snapai://palette` | 打开命令面板 |
| `snapai://model?provider=DeepSeek&model=deepseek-chat` | 持久切换当前供应商和模型 |
| `snapai://model/gpt-4o-mini` | 按模型名切换当前模型 |
| `snapai://model/OpenAI/gpt-4o-mini` | 用路径形式指定供应商和模型 |
| `snapai://model/provider/OpenAI/model/gpt-4o-mini` | 用带标签路径指定供应商和模型 |
| `snapai://context?name=项目A` | 持久切换当前上下文包 |
| `snapai://context/项目A` | 用路径形式切换当前上下文包 |
| `snapai://context?copy=true` | 复制当前上下文包 Markdown |
| `snapai://context/copy/项目A` | 复制指定上下文包 Markdown |
| `snapai://context/effective?copy=true` | 复制实际生效的 System Prompt |
| `snapai://prompt?copy=true` | 复制实际生效的 System Prompt |
| `snapai://context/status?copy=true` | 复制上下文状态摘要,不含正文 |
| `snapai://context?clear=true` | 清空当前上下文包 |
| `snapai://context/clear` | 用路径子命令清空当前上下文包 |
| `snapai://toggle/privacy-preview?enabled=true` | 开启或关闭发送前预览 |
| `snapai://toggle/privacy-preview/on` | 用路径状态开启发送前预览 |
| `snapai://toggle/fallback?enabled=false` | 开启或关闭失败自动切换 |
| `snapai://toggle/history-metadata/on` | 开启历史仅元信息模式 |
| `snapai://work-mode?mode=privacy` | 切换工作模式 |
| `snapai://work-mode/quality` | 用路径形式切换工作模式 |
| `snapai://work-mode/preset/standard` | 用二段式路径切换工作模式 |
| `snapai://routing?preference=quality` | 持久切换 AI 路由偏好 |
| `snapai://routing/fastest` | 用路径形式切换 AI 路由偏好 |
| `snapai://routing/preference/quality` | 用二段式路径切换 AI 路由偏好 |
| `snapai://typewriter?speed=off` | 切换结果打字机速度 |
| `snapai://typewriter/speed/normal` | 用二段式路径切换结果打字机速度 |
| `snapai://dock?enabled=false` | 显示或隐藏 Dock 图标 |
| `snapai://dock/hide` | 用路径状态隐藏 Dock 图标 |
| `snapai://login-item?enabled=true` | 开启或关闭开机启动 |
| `snapai://login-item/enable` | 用路径状态开启开机启动 |
| `snapai://health` | 打开权限健康中心 |
| `snapai://diagnostics?summary=true` | 复制精简权限诊断摘要 |
| `snapai://diagnostics/summary` | 用路径子命令复制精简权限诊断摘要 |
| `snapai://diagnostics?copy=true` | 复制完整权限与安装诊断信息 |
| `snapai://diagnostics/copy` | 用路径子命令复制完整权限与安装诊断信息 |
| `snapai://install-log` | 在 Finder 中显示最近一次安装日志 |
| `snapai://install-log?copy=true` | 复制最近一次安装日志路径 |
| `snapai://install-log/copy` | 用路径子命令复制最近一次安装日志路径 |
| `snapai://update` | 检查更新 |

动作参数既可以传动作名称,也可以传动作 id。URL 中的中文、换行和特殊符号应由调用方按标准 URL 编码。
自动化查找动作时会匹配已启用动作的名称和 id,并忽略空格、连字符、下划线、斜杠和点号等常见分隔符。
URL 命令名支持连字符、下划线和编码空格的常见写法,例如 `snapai://command-palette`、`snapai://command_palette` 和 `snapai:///command%20palette` 都会打开命令面板。
设置页 section 也支持常见别名和分隔符宽容匹配,例如 `api_key` 会打开 AI 模型设置,`screen recording` 会打开权限设置。
URL 参数名会忽略大小写,并把 camelCase、snake_case 和 kebab-case 视为等价,例如 `providerID`、`provider_id` 和 `provider-id` 都可以识别。
支持 host 形式和 path-only 形式,例如 `snapai://model/gpt-4o-mini` 与 `snapai:///model/gpt-4o-mini` 等价。模型名或上下文名包含 `/` 时可按标准 URL 编码为 `%2F`,例如 `snapai://model/openrouter%2Fauto`。
自动化选择供应商、模型或上下文包时,会忽略空格、连字符、下划线、斜杠和点号等常见分隔符,例如 `gpt4omini` 可以匹配 `gpt-4o-mini`。
路由偏好和打字机速度等枚举值也支持这种宽容匹配,例如 `best_quality` 可匹配 `best-quality`,`standard speed` 可匹配 `normal`。
翻译目标语言支持常见缩写和英文别名,并兼容分隔符写法,例如 `zh_cn`、`simplified-chinese`、`Japanese`、`korean_language`。
模型切换 URL 只会选择已经启用的供应商和模型;如果无法匹配,会打开 AI 设置页。
上下文切换和复制 URL 只会选择已经启用且内容非空的上下文包;如果无法匹配,会打开通用设置页。`copy=true` 会复制当前上下文包 Markdown,也可用 `snapai://context/copy/项目A` 复制指定上下文包。`snapai://context/effective?copy=true` 和 `snapai://prompt?copy=true` 会复制实际生效的 System Prompt,包含全局系统提示和当前上下文包。`snapai://context/status?copy=true` 会复制不含正文的上下文状态摘要,适合排查配置问题。`clear=true` 只会清空当前选择,不会删除上下文包。
开关 URL 支持 `privacy-preview`、`redaction`、`history-metadata`、`auto-route` 和 `fallback`;不传 `enabled` 时会翻转当前状态。
工作模式 URL 支持 `standard`、`privacy`、`speed`、`quality`,也支持 `default`、`private`、`fastest`、`best_quality`、`隐私`、`极速`、`质量模式` 等常见别名。
路由偏好 URL 支持 `fastest`、`balanced`、`quality`,也支持 `fast`、`speed`、`best` 等常见别名。
布尔参数支持 `true` / `false`、`on` / `off`、`enabled` / `disabled`、`enable` / `disable`、`是` / `否`、`真` / `假`,也支持 `?copy`、`?export`、`?clear`、`?enabled` 这种只写参数名的 flag 形式。打字机速度 URL 支持 `off`、`slow`、`normal`、`fast`。同一布尔意图出现重复或同义参数时,显式 `false` / `off` 会优先生效;复制、导出、清空等路径子命令遇到对应的显式 `false` / `off` 参数时会被抑制,避免自动化误触副作用。历史清空必须显式传 `clear=true` 或 `clear` flag,普通 `snapai://history` 只会打开历史窗口。
历史导出和历史上下文 URL 支持 `query` / `q` / `search`、`action`、`model`、`tag` 和 `favorite=true` 筛选,筛选逻辑与历史窗口一致。路径子命令同样支持筛选,例如 `snapai://history/export?search=release&favorite` 或 `snapai://history/context?tag=项目A`。从历史创建上下文包时,可用 `name` / `profileName` 指定上下文包名称,用 `limit` / `maxEntries` 控制写入记录数,用 `maxChars` / `maxFieldCharacters` 控制单段原文或结果的最大字符数;会自动跳过空记录和仅元信息记录,并把上下文包设为使用中;如果已存在同名上下文包,会更新原内容而不是重复新增。

`snapai://run`、`snapai://ask`、`snapai://translate`、`snapai://polish`、`snapai://summarize` 和 `snapai://explain` 还支持这些可选参数:

| 参数 | 说明 |
|------|------|
| `provider` / `providerID` | 指定一次性使用的供应商名称或 id |
| `model` / `modelOverride` | 指定一次性使用的模型名 |
| `language` / `lang` | 指定翻译目标语言,例如 `en`、`zh`、`ja`、`ko`、`fr`、`de`、`es` |
| `history` / `saveHistory` | `false` 表示本次结果不保存到历史记录 |
| `replace` / `replaceByDefault` | 覆盖动作的“完成后进入替换确认”标记;出于安全策略,直接 URL 调用没有可信原选区时不会自动写回未知窗口 |

示例:

```text
snapai://run?action=总结&provider=DeepSeek&model=deepseek-chat&history=false&text=...
snapai://translate?lang=en&model=gpt-4o-mini&text=...
```

## 功能概览

- 自定义动作:内置提问、翻译、润色、总结、解释代码,也可新增动作。
- 全局快捷键:每个动作都能设置独立快捷键,设置页会阻止冲突快捷键保存。
- 命令面板:用 `Command + K` 搜索动作、模型、上下文包、路由偏好、历史记录、动作模板、历史导出、Dock/启动/动效设置。
- 工作模式:可一键切换标准、隐私、极速和质量模式,联动隐私预览、本地脱敏、历史保存、自动路由和 fallback。
- 快捷提问面板:无需选中文字,直接输入问题,也支持粘贴图片或截图。
- 取词策略:优先使用 Accessibility API 读取选中文本,失败后才模拟 `Command + C`。
- 多供应商与多模型:支持 OpenAI 兼容协议和 Anthropic 原生协议。
- Keychain 存储:API Key 存入 macOS Keychain,导出配置不会包含密钥。
- Markdown 渲染:支持标题、列表、引用、代码块、加粗、链接等基础格式。
- 替换原文:可把生成结果粘贴回原选区,适合翻译和润色。
- 历史记录:保存最近结果,支持回看、复制和重新发起。
- 历史知识库:历史窗口支持 SQLite FTS、本地语义匹配、收藏、删除、按动作/模型/标签筛选,并可为单条记录添加标签。
- 历史隐私标注:经过本地脱敏、隐私预览或脱敏规则异常的请求会自动写入历史标签,便于筛选和审计。
- 历史隐私模式:可选择只保存动作、时间、模型和标签,不保存原文与 AI 输出。
- 隐私模式本地优先:配置 Ollama 或 LM Studio 后,隐私模式会在自动路由中优先使用本地模型,并在缺少模型或占位 API Key 时给出本地服务恢复提示;本地失败后不会静默切到云端备用模型。
- 上下文包:可保存项目背景、术语表、写作风格或代码栈偏好,并自动合并进请求上下文。
- 动作模板库:可一键创建邮件回复、会议纪要、代码审查、中英双语润色、图片理解等动作,并支持导入/导出 JSON 动作包用于分享。
- macOS 服务菜单:可从支持 Services 的应用中把选中文本直接发送给 SnapAI 提问、翻译或润色。
- 自动化入口:支持 `snapai://` URL Scheme,可从 Shortcuts、Raycast、Alfred 或脚本触发动作。
- 动作工作流诊断:请求诊断会显示输入、隐私、输出和模型策略,便于排查动作执行路径。
- 替换前预览:替换原文前显示原文/新文 Diff,确认后才写回目标应用。
- 文本事务保护:替换和追加会保护用户剪贴板,并尽量恢复触发前的焦点应用。
- 选区来源上下文:捕获选中文字时会识别粗粒度来源类型,帮助 AI 按浏览器、代码编辑器、终端、文档、聊天、邮件或 PDF 语境理解文本。
- 文本捕获诊断:权限健康中心可显示 AX 直读、剪贴板兜底、复制超时、剪贴板保护等取词状态,便于排查不同应用中的兼容性问题。
- 隐私规则测试:脱敏规则可在设置中实时预览替换结果;初始请求、编辑重发、动作/语言切换重发和结果面板追问都会走本地脱敏与发送前确认。
- 默认本地脱敏:内置规则覆盖邮箱、手机号、API Key、访问令牌、URL 参数密钥、JWT 和私钥块;旧版默认规则会在本地升级或导入旧配置时自动迁移到当前规则集。
- 高风险隐私保护:即使关闭发送前预览,检测到高隐私风险的内容也会强制确认;若保存历史,本条记录会自动降级为仅元信息,并写入可筛选的隐私风险标签。复制或导出对话 Markdown 时也会省略高风险正文。
- 请求诊断:可复制路由、fallback、脱敏命中、失效规则、历史保存策略、动作 pipeline 和云端 fallback 审核等元信息,不包含原始敏感正文。
- iCloud 配置同步:可同步供应商结构、动作和快捷键,不包含 API Key 和历史内容。
- 应用内更新:检查 GitHub Release,下载新版 zip,原地替换应用并重启。
- 开机自启:可在设置中开启,基于 `SMAppService`。

## AI 配置示例

| 服务 | 协议 | Base URL | 模型名 |
|------|------|----------|--------|
| OpenAI | OpenAI 兼容 | `https://api.openai.com/v1` | `gpt-4o-mini` |
| DeepSeek | OpenAI 兼容 | `https://api.deepseek.com/v1` | `deepseek-chat` |
| Ollama 本地 | OpenAI 兼容 | `http://localhost:11434/v1` | `llama3.1` |
| LM Studio 本地 | OpenAI 兼容 | `http://localhost:1234/v1` | `local-model` |
| Claude | Anthropic 原生 | `https://api.anthropic.com/v1` | `claude-sonnet-4-6` |

安全限制:

- 非本机 HTTP 端点会被拒绝,避免 API Key 通过明文网络发送。
- 本机 HTTP 仅用于 `localhost`、`127.0.0.1`、`::1`,主要服务 Ollama、LM Studio 等本地模型。
- 使用隐私模式时,如果已启用可请求的本地模型,自动路由会优先选择本地端点;手动关闭自动路由时仍尊重当前选中的模型。
- 本地 OpenAI 兼容服务通常仍需要在 SnapAI 中填写一个非空 API Key 占位符。Ollama 可填 `ollama`,LM Studio 可填 `lm-studio`。

## 更新机制

SnapAI 的菜单里有“检查更新”。发现新版本后,你可以选择“安装并重启”。

当前实现会:

1. 在应用内通过 macOS 网络栈请求 GitHub Releases 最新版本,不依赖终端、`gh` 或 `curl`。
2. 优先使用 GitHub API；如果 API 返回 403 或临时不可用,会回退到 GitHub 普通 Release 页面获取最新版本标签。
3. 找到或构造 Release 里的 SnapAI zip 资产下载地址。
4. 同时下载 `snapai-manifest-vX.X.X.json` 和 `snapai-manifest-vX.X.X.json.sig`。
5. 使用应用内置公钥先验证 manifest 签名,再信任 manifest 中的 zip SHA256、bundle id、designated requirement 和证书指纹。
6. 下载 zip 到临时目录,校验 SHA256 后解压。
7. 校验解压出的 `SnapAI.app` bundle id 与当前应用一致。
8. 使用 `codesign --verify --deep --strict` 做基础签名校验,并比较当前 App 与更新包的 designated requirement。
9. 用脱离当前应用生命周期的临时安装脚本等待当前 SnapAI 进程退出。
10. 在原安装路径替换应用。
11. 对替换后的应用执行:

```bash
xattr -cr "$APP_PATH"
```

12. 使用 `open -n -F` 自动重新打开 SnapAI；如果首次打开失败,会重试并把过程写入临时安装日志。

因此,应用已经正常启动以后,后续应用内更新会尽量自动处理 quarantine。首次从 GitHub 下载时,因为应用尚未运行,仍需要用户手动执行 `xattr -cr`。

如果自动更新提示安装位置不可写,请把 `SnapAI.app` 移动到 `~/Applications` 后再试。应用内更新需要能够写入当前安装目录。

## 辅助功能权限与签名

macOS 的辅助功能权限和应用的代码身份有关。SnapAI 当前没有 Apple Developer ID,所以发布包不是 Apple 公证应用。

当前仓库提供两种构建签名方式:

- 有稳定签名身份时:`build.sh` 会使用 `CODESIGN_IDENTITY` 或 `SnapAI Local Signing`。
- 日常开发构建没有稳定签名身份时,`build.sh` 会回退到 ad-hoc 签名。
- 正式 release 构建必须使用稳定签名身份;`SNAPAI_RELEASE=1` 或 `./build.sh --release` 不会回退到 ad-hoc。

ad-hoc 签名每次构建都可能让代码身份变化,更新后更容易被系统要求重新授予辅助功能权限。为了减少这种情况,可以创建本机自签名代码签名证书:

```bash
./scripts/create-local-signing-identity.sh
./build.sh
```

正式打包请使用:

```bash
SNAPAI_RELEASE=1 ./build.sh --release
```

注意:

- 自签名不等同于 Apple Developer ID 或 notarization。
- 首次从旧 ad-hoc 版本切换到自签名版本时,macOS 可能仍会要求重新授予一次辅助功能权限。
- 后续只要继续使用同一个证书构建,代码身份会更稳定,可减少重复授权。
- 对其他用户的机器来说,自签名证书默认不受系统信任,所以首次 GitHub 下载仍可能需要 `xattr -cr`。

钥匙串访问也遵循同样的代码身份规则。API Key 保存在 macOS Keychain 中,如果某次更新包换了签名证书或 Bundle ID,系统可能会把新版 SnapAI 视为另一个应用,从而重新询问钥匙串访问权限。

为降低误更新风险,应用内更新会在安装前验证签名 manifest,并比较当前 App 与更新包的 designated requirement。若发现 manifest 缺失、签名无法验证、bundle id 不一致或签名身份不一致,会取消自动安装并提示原因。开源/无 Apple Developer 账号发布时,请务必保留同一个自签名证书的私钥,不要每次 release 重新生成证书。

## 构建

本项目是 SwiftPM 结构,但当前构建脚本直接用 `swiftc` 编译并组装 `.app`:

```bash
./build.sh
```

构建成功后会生成:

```text
SnapAI.app
```

如果你要打包 Release:

```bash
scripts/preflight-release.sh
```

`scripts/preflight-release.sh` 会依次运行空白检查、逻辑测试、`swift build`、`./build.sh`、签名校验、版本一致性检查、Release zip/manifest 打包、manifest 校验,并解压 zip 验证其中的 `SnapAI.app` 结构、版本和签名。真正发布前建议使用:

```bash
scripts/preflight-release.sh --require-clean
```

日常开发只想快速确认构建和测试,可以跳过打包:

```bash
scripts/preflight-release.sh --skip-package
```

`scripts/package-release.sh` 会生成干净的 zip、`snapai-manifest-vX.X.X.json` 和 `snapai-manifest-vX.X.X.json.sig`,并写入 zip 的 SHA256、bundle id、designated requirement 和证书指纹。正式 release 默认要求 manifest 签名私钥可用;脚本会校验 manifest 的版本、资产名、SHA256、签名身份和签名文件是否匹配当前 zip,也会解压 zip 验证 `SnapAI.app` 的版本和签名。

## 常见问题

### 双击提示应用损坏怎么办

先确认已经把应用移动到固定位置,然后执行:

```bash
xattr -cr /Applications/SnapAI.app
open /Applications/SnapAI.app
```

### 快捷键没有反应怎么办

检查三件事:

1. 系统设置里是否给 SnapAI 授予了辅助功能权限。
2. 设置页里动作是否启用,快捷键是否冲突。
3. 当前应用中是否真的选中了可复制的文本。

### 为什么替换原文失败

替换原文依赖辅助功能权限和模拟粘贴。请确认:

- SnapAI 有辅助功能权限。
- 目标应用允许粘贴。
- 触发动作后不要立即切换到其他输入位置。

### API Key 会不会导出或同步

不会。API Key 存在 macOS Keychain 中。配置导出和 iCloud 配置同步都不包含 API Key。

### iCloud 会同步历史记录吗

不会。iCloud 只同步配置结构,例如供应商、动作、快捷键、系统 Prompt 等;不会同步历史记录、统计、窗口尺寸或 API Key。

## 项目结构

```text
Sources/SnapAI/
  main.swift            应用入口
  AppDelegate.swift     菜单栏、主菜单、快捷键、取词到结果窗流程
  Settings.swift        设置模型与 UserDefaults 持久化
  Provider.swift        AI 供应商与模型配置
  Action.swift          自定义动作与翻译目标语言
  ActionTemplateLibrary.swift 动作模板库、导入导出与分享包格式
  SelectionSourceContext.swift 选区来源分类与非敏感上下文提示
  AIClient.swift        OpenAI / Anthropic 流式请求
  AIRequestRouter.swift AI 路由、fallback 诊断与模型选择
  RequestSession.swift  请求会话输入快照
  StreamingAccumulator.swift 流式输出与 thinking 提取
  FallbackRunner.swift  失败路由与备用模型决策
  TextCapture.swift     Accessibility 取词与复制兜底
  ServicePasteboardText.swift macOS 服务菜单文本解析
  ResultViewModel.swift 结果窗状态机
  ResultView.swift      结果窗 UI
  ResultPersistence.swift 结果历史保存
  ResultWriteBackCoordinator.swift 结果替换/追加协调
  TextEditTransaction.swift 替换/追加事务与剪贴板保护
  TextDiff.swift        替换前 Diff 计算
  DiffPreviewWindow.swift 替换前预览窗口
  MarkdownView.swift    轻量 Markdown 渲染
  FloatingPanel.swift   浮动面板
  QuickInput.swift      快捷提问面板
  SettingsView.swift    设置界面
  HistoryStore.swift    SQLite 历史记录与 FTS 搜索
  HistoryWindow.swift   历史记录独立窗口
  ContextProfile.swift  上下文包
  RoutingMetrics.swift  本机路由表现数据
  ModelCapability.swift 模型能力推断与路由依据
  MenuCoordinator.swift 菜单构建辅助
  HotKeyCoordinator.swift 全局快捷键注册协调
  HotKeyManager.swift   Carbon 全局快捷键注册
  HotKeyRecorder.swift  快捷键录制控件
  AutomationRouter.swift 自动化 URL 路由辅助
  WindowCoordinator.swift 设置窗口与置顶状态管理
  Keychain.swift        API Key 存储
  iCloudSync.swift      iCloud 配置同步
  UpdateChecker.swift   GitHub Release 检查与应用内更新
  LoginItem.swift       开机自启
  OnboardingView.swift  首次启动引导
Resources/
  Info.plist
  AppIconLight.icns
  AppIconDark.icns
scripts/
  create-local-signing-identity.sh
build.sh
Tests/SnapAILogicTests/
  main.swift                 测试入口与执行清单
  UpdateCheckerTests.swift   更新器、manifest 与签名校验
  RoutingTests.swift         AI 路由、fallback、请求诊断与流式累积
  WriteBackTests.swift       文本捕获、Services、写回与剪贴板保护
  PrivacyTests.swift         隐私预览、脱敏规则与隐私标签
  CommandPaletteTests.swift  命令面板、菜单、快捷键和自动化命令
  SettingsMigrationTests.swift 设置迁移、导入导出与 iCloud payload
  HistoryTests.swift         SQLite/FTS 历史、筛选和上下文包
```
