# Fuck My Shit Mountain Audit Report

**Project:** SnapAI
**Audit mode:** full
**Date:** 2026-07-11
**Reviewer:** Codex / GPT-5

---

## 1. Executive Summary

SnapAI 已具备较完整的 macOS 菜单栏 AI 助手能力：网络请求有超时与本机 HTTP 限制，敏感信息有脱敏和本地加密存储，历史记录使用 SQLite + FTS，并且已有构建、smoke、供应链和 release preflight 门禁。`swift build`、项目自带 logic test wrapper、macOS smoke 和 remediation gate 均通过，说明当前主干具备继续演进的可靠基础。

主要风险集中在“状态是否真的持久化”“长文本 UI 性能”“测试真实性”和 target 边界。历史操作先更新内存再忽略 SQLite 失败，会让用户看到成功但重启后状态反弹；打字机渲染每个 tick 都重新遍历和复制前缀，长输出会放大 CPU 与临时内存；兼容测试 runner 漏执行 1 个隐私测试；41 个 symlink 仍让 app target 与 `SnapAILogic` 产生同名模型边界。发布文档还存在过期总览图和缺失许可证文件。建议先修复数据一致性、测试完整性和长文本性能，再继续按簇消除 symlink，随后集中改善截图交互和无障碍标签。

### Score Dashboard

```text
Security        ████████░░  8.2  A   网络、密钥和诊断脱敏边界较完整；本轮源码与脚本覆盖为 High，未做第三方动态渗透。
Stability       ███████░░░  6.8  B   构建与 smoke 稳定，但历史写入失败会造成内存状态和持久化状态分叉。
Performance     ███████░░░  6.5  B   多处资源已有上限，但长输出打字机路径存在重复 String 遍历与前缀复制。
Testing         ██████░░░░  6.2  B   216 个逻辑测试函数覆盖广，但统一入口漏注册 1 个隐私测试，且本机标准 XCTest 不可用。
Maintainability ██████░░░░  5.5  B   结构清晰度在改善，但 41 个 symlink、多个 500+ 行文件和跨 target 同名类型仍提高变更成本。
Design          ██████░░░░  5.8  B   已有 logic target 和 bridge 方向，但边界迁移未完成，UI 与业务状态仍有局部耦合。
Release         ██████░░░░  6.0  B   CI、签名 manifest、SBOM 与 preflight 较完整；许可证缺失且 1.6.52 全量 release preflight 尚未在干净工作树证明。
─────────────────────────────────────
Overall         ██████░░░░  6.4  B
```

### Finding Statistics

| Severity | Count | Confirmed | Suspected |
|----------|-------|-----------|-----------|
| Critical | 0 | 0 | 0 |
| High | 0 | 0 | 0 |
| Medium | 6 | 6 | 0 |
| Low | 2 | 2 | 0 |
| Info | 0 | 0 | 0 |
| **Total** | **8** | **8** | **0** |

## 2. Project Map

- 入口：`Sources/SnapAI/main.swift` 启动 `AppDelegate`；菜单栏、全局快捷键、快捷输入、结果面板、设置、历史窗口和自动化 URL 由 app target 管理。
- 核心逻辑：`Sources/SnapAILogic` 提供命令描述、路由、导出、写回协调和测试友好的值对象；其中 35 个为真实源码，41 个仍是指向 `Sources/SnapAI` 的 symlink。
- AI 数据流：文本/截图捕获 → 隐私预览与脱敏 → `AIRequestRouter` 候选排序 → `AIClient` 流式请求 → `StreamingAccumulator` → `ResultViewModel` → 复制/替换/追加/历史持久化。
- 状态所有权：`AppSettings` 持有用户配置、运行偏好和内存历史；`HistoryStore` 持久化 SQLite/FTS；`LocalSecretStore` 保存本地 AES.GCM 密钥与 provider secret；`iCloudSync` 同步去密钥后的配置。
- 外部接口：Accessibility、Pasteboard、ScreenCapture、GitHub Releases、OpenAI-compatible/Anthropic API、`snapai://` URL Scheme、SQLite、文件系统和独立 updater helper。
- 发布：GitHub Actions 执行 build/test/边界/供应链检查；本地 `preflight-release.sh` 负责 smoke、签名、打包、manifest、SBOM 和安装包验证。
- 排除：`.build`、`dist`、二进制 app bundle、PNG/ICNS 内容和真实线上模型服务未做深度检查；未安装额外漏洞扫描器，因为项目无外部 SwiftPM dependency。

### Coverage Matrix

| Dimension | Coverage | Evidence inspected | Exclusions / limits |
|-----------|----------|--------------------|---------------------|
| Architecture | High | Package.swift、全部 source 清单、symlink manifest、迁移脚本 | 未做历史提交依赖图 |
| Security | High | AIClient、LocalSecretStore、UpdateChecker、隐私测试与供应链脚本 | 未做动态渗透 |
| Stability | High | 错误路径搜索、HistoryStore、TextCapture、smoke、logic tests | 未注入真实网络/磁盘故障 |
| Performance | Medium | 字符串、缓存、历史上限、截图与 streaming 热点 | 未采集 Instruments/ETTrace |
| Testing | High | Package test target、runner、216 个测试函数、执行结果 | 本机 XCTest 模块缺失 |
| Maintainability | High | 文件行数、声明清单、target 边界、重复/超大文件搜索 | 未做完整复杂度工具扫描 |
| Design | High | UI/logic dependency、bridge、AppDelegate extensions | 未做全量调用图 |
| Release | High | CI、build、preflight、package、SBOM、版本与文档 | 未执行需要私钥和干净工作树的正式打包 |
| Documentation | High | README、1.6.52 notes/report、迁移计划、SVG | 未检查外部 GitHub 页面内容 |
| Configuration | High | Settings 解码/归一化、Info.plist、provider config | 未测试所有 provider 组合 |
| Observability | Medium | diagnostics、routing metrics、history status、install log | 无集中日志/metrics backend，桌面应用不强制要求 |
| Data Integrity | High | SQLite 事务、history mutation、iCloud payload | 未模拟断电 |
| Privacy | High | 脱敏、历史模式、导出、secret store、隐私测试 | 未检查云服务实际保留策略 |
| Accessibility | Medium | SwiftUI/AppKit 控件、accessibility modifier 搜索 | 未做 VoiceOver 全流程实测 |
| Supply Chain | High | 无外部 dependency、SHA-pinned action、SBOM、签名 manifest | 未验证真实发布私钥 |
| Cost | Medium | token/image/request limits、routing、history/resource caps | 未调用真实计费 API |
| AI Safety | High | prompt payload、privacy eval、fallback、tool/action边界 | 应用无自主高权限 agent tool loop |
| Fallback | High | FallbackRunner、HistoryStore、配置 decode、错误诊断 | 未覆盖每个 OS API 异常 |
| Testing Authenticity | High | runner 注册、测试组织、实际执行 | 没有覆盖率工具结果 |
| Type Safety | High | force cast/try 搜索、边界 DTO、Codable 输入 | 第三方响应仍使用动态 JSON 字典 |
| Frontend State | High | ResultViewModel、QuickInput、Settings UI state | 未运行 SwiftUI diff profiler |
| Backend API | Not assessed | 项目为本地桌面客户端，无自建 backend endpoint | 不适用 |
| Dependency Weight | High | Package.swift、show-dependencies、供应链脚本 | 系统 framework 体积未单独测量 |
| Code Consistency | Medium | 命名、错误处理、文件结构、bridge 模式 | 未配置 SwiftLint/swift-format |
| Comment Coverage | Medium | public API、关键并发/安全注释、README | 未逐个 public symbol 统计 |

## 3. Top Risks

1. Medium — 历史操作忽略 SQLite 失败，造成 UI 与持久化状态分叉。
2. Medium — 长输出打字机每 tick 重建完整前缀，CPU 和临时内存随文本增长显著放大。
3. Medium — 41 个 symlink 维持跨 target 同名类型，重构容易出现类型边界和测试偏差。
4. Medium — logic suite 漏注册 1 个隐私回归测试，绿色结果不代表完整执行。
5. Medium — 截图操作没有 in-progress 状态，重复点击可排队多个 capture 并导致窗口反复隐藏/恢复。
6. Medium — 公共仓库发布说明声称存在许可证文件，但仓库中没有 LICENSE/COPYING。
7. Low — 多个 icon-only 编辑按钮缺少面向任务的 accessibility label。
8. Low — README 的 1.6.52 UI 总览实际仍绘制 1.6.34 文案。

## 4. Detailed Findings

### Finding: 历史修改忽略 SQLite 持久化失败

- Severity: Medium
- Confidence: High
- Category: Stability
- Status: Confirmed
- Affected area: 历史记录删除、清空、收藏与标签编辑
- Evidence:
  - File: Sources/SnapAI/AppSettingsHistory.swift:25-56
  - Function / Module: addHistory、clearHistory、deleteHistory、toggleHistoryFavorite、updateHistoryTags
  - Relevant behavior: 先修改内存数组，再调用返回 Bool 的 HistoryStore 方法，但完全忽略失败结果并继续 save。
- Problem: UI 状态可在 SQLite 写入失败时表现为成功，随后在重启或重新加载后恢复旧值；清空与删除属于用户明确要求的隐私/数据操作，不能静默失败。
- Why it matters: 状态分叉会降低用户对历史管理的信任，并使诊断与恢复更加困难。
- Realistic failure scenario: Application Support 目录不可写或 SQLite 暂时失败，用户删除敏感历史；当前窗口立即消失，但数据库仍保留记录，重启后记录重新出现。
- Minimal fix: 让 mutation 只在 HistoryStore 成功后提交内存状态，或失败时回滚并返回明确结果供 UI 显示。
- Better long-term fix: 引入单一 HistoryRepository，以持久化成功作为状态提交点，并统一发布可观察错误状态。
- Regression test suggestion: 使用被文件占用的临时路径构造 HistoryStore，验证 delete/clear/tag/favorite 失败后内存状态不伪装成功且 UI 可获得错误。
- Estimated effort: 3-5 hours

### Finding: 打字机渲染对长输出重复遍历和复制字符串

- Severity: Medium
- Confidence: High
- Category: Performance
- Status: Confirmed
- Affected area: 流式结果面板
- Evidence:
  - File: Sources/SnapAI/ResultViewModel.swift:645-665
  - Function / Module: ResultViewModel.tick
  - Relevant behavior: 每个 tick 多次计算 output.count/fullText.count，从 fullText.startIndex 重新 offset，并创建从头到目标位置的新 String。
- Problem: Swift String 的 count 和 offsetBy 对扩展字形不是常数时间，且每次都复制越来越长的前缀；输出越长，总工作量越接近二次方增长。
- Why it matters: 长回答、代码和多字节文本会造成主线程卡顿、额外分配和窗口响应下降。
- Realistic failure scenario: 模型流式生成数万字符代码，打字机保持开启；每个 timer tick 在 MainActor 上重新扫描并分配更大的字符串，导致滚动、按钮和窗口拖动明显卡顿。
- Minimal fix: 保存已显示的 String.Index 或消费增量 chunk，只追加下一段，不从起点重建前缀。
- Better long-term fix: 把流式 buffer 与显示节流建模为可测试的 logic 类型，并用批量时间预算驱动 UI 更新。
- Regression test suggestion: 为 50k 字符 ASCII/Emoji 输出增加增量推进测试和基准，验证每个 tick 只处理新增片段。
- Estimated effort: 3-6 hours

### Finding: SnapAILogic 仍有 41 个 symlink 造成跨 target 同名类型

- Severity: Medium
- Confidence: High
- Category: Maintainability
- Status: Confirmed
- Affected area: app/logic target 架构边界
- Evidence:
  - File: Package.swift:10-38
  - Function / Module: SnapAI 与 SnapAILogic targets
  - Relevant behavior: scripts/check-logic-symlinks.sh 当前验证结果为 41 symlinks、35 real sources；迁移分析显示大部分为 cluster 或 app-api 边界。
- Problem: 同一源码分别在两个 module 编译，形成结构相同但类型身份不同的模型，迫使 bridge/DTO 和批量迁移，增加维护与测试复杂度。
- Why it matters: 小改动可能需要同时考虑 app-local 与 SnapAILogic 类型，容易出现错误 import、public API 扩张和测试只覆盖其中一侧。
- Realistic failure scenario: 单独迁移一个使用 AIRequestRoute 的文件后，app 传入 app-local AIRequestRoute，而 logic API 需要 SnapAILogic.AIRequestRoute，构建失败或引入重复转换。
- Minimal fix: 按迁移报告选择最小 cluster，先定义 DTO/port，再一次性迁移并降低 symlink 基线。
- Better long-term fix: 让所有非 UI/OS orchestration 模型只存在于 SnapAILogic，app target 仅保留 SwiftUI/AppKit adapter。
- Regression test suggestion: 每次迁移后运行边界脚本、logic suite、swift build，并增加禁止 app target 定义已迁移顶层类型的门禁。
- Estimated effort: 多阶段，2-5 天

### Finding: 统一 logic suite 漏执行一个隐私测试

- Severity: Medium
- Confidence: High
- Category: Testing
- Status: Confirmed
- Affected area: SnapAILogicTests 注册入口
- Evidence:
  - File: Tests/SnapAILogicTests/main.swift:820-950
  - Function / Module: runAllLogicTests
  - Relevant behavior: 仓库声明 216 个 test* 函数，但入口只调用 215 个；缺少 testPrivacySubmissionPreviewDetectsExpandedSecretFormatsWhenRedactionDisabled。
- Problem: 标准 XCTest wrapper 和 swiftc compatibility runner 都调用同一个 runAllLogicTests，因此两条路径都会漏掉该隐私回归测试。
- Why it matters: 测试输出为绿色时仍可能没有覆盖新增的 secret format 检测，形成虚假信心。
- Realistic failure scenario: 后续修改隐私检测导致 expanded secret format 回归；CI 与本地 runner 都通过，因为该函数从未被调用。
- Minimal fix: 把缺失测试加入 runAllLogicTests，并在脚本中自动比较声明与注册集合。
- Better long-term fix: 将测试迁移为 XCTest 自动发现，compatibility runner 由生成清单或静态门禁保证同步。
- Regression test suggestion: 新增 shell gate，要求所有顶层 test* 声明恰好在 runAllLogicTests 中出现一次。
- Estimated effort: 1-2 hours

### Finding: 截图操作缺少进行中状态和重复触发保护

- Severity: Medium
- Confidence: High
- Category: Stability
- Status: Confirmed
- Affected area: 快捷输入截图 UX
- Evidence:
  - File: Sources/SnapAI/QuickInput.swift:124-142,209-281
  - Function / Module: QuickInputView、QuickInputController.captureScreen
  - Relevant behavior: 截图按钮始终可用，model 没有 isCapturing；每次点击都会隐藏窗口并向串行 captureQueue 提交新 Process。
- Problem: 用户无法判断截图是否正在处理，也可以在 300ms 隐藏延迟和最长 15 秒命令期间重复触发。
- Why it matters: 多次 capture 会造成窗口反复隐藏/恢复、结果覆盖和“应用消失”的错误感知。
- Realistic failure scenario: 屏幕录制响应较慢时用户连续点击截图；多个任务依次运行，旧截图晚到并覆盖用户预期的新状态。
- Minimal fix: 增加 isCapturing，开始时禁用截图/发送并显示 ProgressView，结束或失败时统一复位。
- Better long-term fix: 将截图流程封装为可取消的单一 task，并为替换、取消和超时定义明确状态机。
- Regression test suggestion: 连续触发两次 capture，断言只启动一个任务、按钮为 disabled，完成后恢复且仅提交一次结果。
- Estimated effort: 2-4 hours

### Finding: 公共发布缺少实际许可证文件

- Severity: Medium
- Confidence: High
- Category: Release
- Status: Confirmed
- Affected area: GitHub 分发与使用条款
- Evidence:
  - File: README.md:308
  - Function / Module: 许可证章节
  - Relevant behavior: README 表示“请以仓库中的许可证文件为准”，但仓库没有 LICENSE、COPYING 或等价文件。
- Problem: 用户和贡献者无法从仓库确认复制、修改和分发权限，文档引用的 source of truth 不存在。
- Why it matters: 对公开二进制和源代码发布而言，这是实际采用和合规阻碍。
- Realistic failure scenario: 用户准备在团队内分发或贡献补丁时无法判断授权范围，只能停止采用或承担不必要法律风险。
- Minimal fix: 由项目所有者选择并提交明确 LICENSE，同时让 README 直接链接该文件。
- Better long-term fix: 在 release preflight 中检查许可证文件存在，并在 SBOM/release notes 中记录 license metadata。
- Regression test suggestion: preflight 检查 LICENSE 文件存在且 README 链接可解析。
- Estimated effort: 30 minutes（需要项目所有者决定许可证）

### Finding: 编辑界面的 icon-only 按钮缺少任务语义标签

- Severity: Low
- Confidence: High
- Category: Maintainability
- Status: Confirmed
- Affected area: 动作和供应商排序、模型添加
- Evidence:
  - File: Sources/SnapAI/ActionSettingsSection.swift:147-149; Sources/SnapAI/ProviderSettingsSection.swift:266-270,367
  - Function / Module: actionCard、providerCard/model editor
  - Relevant behavior: 只渲染 chevron/plus Image，部分有 help，但没有包含对象名称的 accessibilityLabel。
- Problem: VoiceOver 可能只读出通用 SF Symbol 名称，不能说明“上移动作 X”或“为供应商 Y 添加模型”。
- Why it matters: 键盘和辅助技术用户需要从上下文辨识高频编辑操作。
- Realistic failure scenario: VoiceOver 焦点落在多个相同 chevron 按钮上，用户无法判断当前按钮操作的是哪个动作或供应商。
- Minimal fix: 为按钮添加动态 accessibilityLabel/Hint，并保持 help 与 label 一致。
- Better long-term fix: 抽取可复用的 ReorderButton/NamedIconButton 组件统一 label、hint、disabled 和 hit target。
- Regression test suggestion: UI/accessibility 检查关键 icon-only 控件的 label 包含对象名称和动作动词。
- Estimated effort: 1-2 hours

### Finding: 1.6.52 README 引用的 UI 总览仍显示 1.6.34

- Severity: Low
- Confidence: High
- Category: Release
- Status: Confirmed
- Affected area: README 首屏与版本展示
- Evidence:
  - File: README.md:5; docs/snapai-ui-overview.svg:5,75
  - Function / Module: UI overview asset
  - Relevant behavior: README alt text 已更新为 1.6.52，但 SVG 标题和底部重点仍写 1.6.34。
- Problem: 首屏版本信息与当前 release 不一致，用户无法确认截图是否代表新版功能。
- Why it matters: 过期视觉材料降低发布可信度并增加支持沟通成本。
- Realistic failure scenario: 用户根据 1.6.34 图判断 1.6.52 功能，误认为新版没有后续设置和迁移改进。
- Minimal fix: 更新 SVG 版本和当前重点，或改成不绑定版本号的稳定产品总览。
- Better long-term fix: release 时自动验证 README 引用资产中的版本文本，或使用真实截图并只在重大 UI 变化时更新。
- Regression test suggestion: preflight 搜索 README 当前版本并验证引用 SVG/文档不包含更旧的显式版本标题。
- Estimated effort: 30-60 minutes

## 5. Architecture Concerns

- Coverage: High
- Inspected evidence: Package.swift、156 个 Swift source、symlink 清单、迁移脚本和 bridge 文件。
- Exclusions / limits: 未生成完整调用图。

主要问题是 finding 3；现有按 `cluster/app-api/isolated` 分类的迁移策略方向正确，应继续降低 symlink 基线而不是扩大 bridge 数量。

## 6. Security Concerns

- Coverage: High
- Inspected evidence: LocalSecretStore、AIClient、UpdateChecker、隐私脱敏和 supply-chain 脚本。
- Exclusions / limits: 未做动态攻击测试。

未发现 High/Critical 安全问题。HTTP 仅允许本机、请求体有图片上限、错误输出会脱敏、manifest/zip 有签名与 hash 验证。许可证缺失属于发布治理而非安全漏洞。

## 7. Stability Concerns

- Coverage: High
- Inspected evidence: HistoryStore、AppSettingsHistory、ResultViewModel、TextCapture、QuickInput、smoke。
- Exclusions / limits: 未模拟真实磁盘满和 OS API 崩溃。

finding 1 和 finding 5 是当前最直接的用户可见稳定性问题。

## 8. Performance Concerns

- Coverage: Medium
- Inspected evidence: streaming、TextDiff、history caps、image caps、routing metrics。
- Exclusions / limits: 未运行 Instruments。

finding 2 是主要热点；TextDiff 已设置 LCS cell limit，历史和图片也有明确上限，是良好实践。

## 9. Testing Gaps

- Coverage: High
- Inspected evidence: 216 个顶层 test 函数、runAllLogicTests、runner、CI 与实际执行。
- Exclusions / limits: 本机 XCTest 模块不可用。

finding 4 必须先修复；随后应补 history persistence failure 和 capture single-flight 测试。

## 10. Maintainability Concerns

- Coverage: High
- Inspected evidence: 文件行数、模块声明、AppDelegate extensions、logic target。
- Exclusions / limits: 无自动复杂度评分。

finding 3 是系统性债务；此外 UpdateChecker、RoutingDiagnostics、AppDelegate、History 等 500+ 行文件需要按职责渐进拆分，但不建议一次性重写。

## 11. Design / Principles Concerns

- Coverage: High
- Inspected evidence: 状态所有权、UI/business coupling、bridge 与 persistence flow。
- Exclusions / limits: 未审查每个私有 helper。

- Principle 1.1 SRP：部分大文件同时承担状态、IO、格式化和 UI orchestration。
- Principle 5.3 No Hidden Side Effects：历史 mutation 名称没有表达持久化可能失败，且返回 Void。
- Principle 7.1 Dependency Rule：symlink 使 target 边界仍是过渡态。
- Principle 10.2 Unbounded Resources：大多数资源已有上限；stream 显示成本虽有 token 上限，仍需增量化。

## 12. Release Concerns

- Coverage: High
- Inspected evidence: CI、preflight、package、Info.plist、README、release notes。
- Exclusions / limits: 未执行正式私钥签名与上传。

finding 6 和 finding 8 需在下次正式 release 前完成；当前 1.6.52 工作树未干净，因此不能把 release notes 中的 preflight 条目视为已证明。

## 13. Documentation Analysis

- Coverage: High
- Inspected evidence: README、1.6.52 notes/report、迁移计划、SVG。
- Exclusions / limits: 外部 Releases 页面未检查。

README 的功能、隐私、更新和构建说明总体详尽；finding 6/8 是明确不一致。

## 14. Configuration Safety Analysis

- Coverage: High
- Inspected evidence: AppSettings decode/sanitize、provider timeout/token/model、Info.plist。
- Exclusions / limits: 未枚举所有旧 schema payload。

配置边界普遍有 clamp/sanitize；API Key 不进入 UserDefaults/iCloud/export。未发现需要单独立项的配置风险。

## 15. Observability / Operability Analysis

- Coverage: Medium
- Inspected evidence: diagnostics、routing metrics、HistoryStore latestStatus、install log。
- Exclusions / limits: 本地桌面应用没有集中 telemetry backend。

已有权限健康中心和脱敏诊断。历史 mutation 应把持久化失败转化为可见状态，而不是只更新静态 latestStatus。

## 16. Data Integrity Analysis

- Coverage: High
- Inspected evidence: SQLite WAL/transaction/prune、settings migration、iCloud revision。
- Exclusions / limits: 未做 crash consistency harness。

finding 1 是核心数据一致性问题；HistoryStore 内部 transaction 使用正确，但调用层没有尊重结果。

## 17. Privacy / Data Governance Analysis

- Coverage: High
- Inspected evidence: privacy preview、redaction、metadata-only history、export safety、secret store。
- Exclusions / limits: 外部 provider 数据政策不在仓库控制范围。

隐私设计整体较强；正因如此，删除/清空静默失败更需要优先修复。finding 4 漏掉的也是隐私回归测试。

## 18. Accessibility / UX Correctness Analysis

- Coverage: Medium
- Inspected evidence: SwiftUI/AppKit 控件和 accessibility modifier 搜索。
- Exclusions / limits: 未运行 VoiceOver。

finding 5 和 finding 7 是明确问题。结果输入已为 NSTextView 设置 label/help，是正向实践。

## 19. Supply Chain / Reproducibility Analysis

- Coverage: High
- Inspected evidence: SHA-pinned checkout、无外部 SwiftPM dependency、SBOM、manifest 签名和 preflight。
- Exclusions / limits: 未验证真实 key material。

供应链设计优于同规模项目；许可证文件属于包治理缺口。

## 20. Cost / Resource Economics Analysis

- Coverage: Medium
- Inspected evidence: token/image limits、timeouts、fallback 路由、history caps。
- Exclusions / limits: 无真实 token spend 数据。

未发现无界模型循环或自主 tool loop。长输出 UI 成本由 finding 2 覆盖。

## 21. AI / LLM Safety Analysis

- Coverage: High
- Inspected evidence: payload composition、隐私 preview、fallback、安全 HTTP、prompt privacy eval。
- Exclusions / limits: 未调用真实模型红队。

应用不会让模型直接执行任意工具；主要风险是用户内容与模型输出可靠性，现有预览、诊断与显式 fallback 边界合理。

## 22. Fallback / Defensive Code Analysis

- Coverage: High
- Inspected evidence: FallbackRunner、try? 搜索、HistoryStore、settings decode。
- Exclusions / limits: 未逐个第三方 API 错误码注入。

大多数 fallback 有用户提示；HistoryStore 的 Bool 结果在调用层被忽略，是本轮最重要的 silent fallback。

## 23. Testing Authenticity Analysis

- Coverage: High
- Inspected evidence: test declaration/registration diff、runner 实际执行。
- Exclusions / limits: 无覆盖率报告。

测试大多直接验证业务行为，mock 较少；finding 4 证明手写注册清单会产生真实漏测。

## 24. Type Safety Analysis

- Coverage: High
- Inspected evidence: try!/as!/fatalError 搜索、Codable 和动态 JSON 边界。
- Exclusions / limits: 模型响应仍依赖 JSONSerialization 字典。

强制转换很少。动态 provider response 解析是合理边界，但需要继续用安全 cast 和明确错误保持约束。

## 25. Frontend State Analysis

- Coverage: High
- Inspected evidence: ResultViewModel、QuickInputModel、Settings UI state、timer/task 生命周期。
- Exclusions / limits: 未运行 SwiftUI render profiler。

finding 2/5 直接涉及 UI 状态；建议把显示节流和截图流程提取为小型状态机，减少 ViewModel 的隐式状态组合。

## 26. Backend API Analysis

- Coverage: Not assessed
- Inspected evidence: Package 和 source map 未发现自建服务端 endpoint。
- Exclusions / limits: SnapAI 仅消费外部 provider API。

不适用。

## 27. Dependency Weight Analysis

- Coverage: High
- Inspected evidence: Package.swift、swift package show-dependencies、supply-chain scan。
- Exclusions / limits: 系统 framework 体积未拆分。

项目没有外部 SwiftPM dependency，不存在明显 dependency weight 问题。

## 28. Code Consistency Analysis

- Coverage: Medium
- Inspected evidence: bridge 命名、error handling、文件组织、注释搜索。
- Exclusions / limits: 未配置 formatter/linter。

整体命名一致；主要不一致来自过渡期 app-local 类型与 SnapAILogic public 类型并存。

## 29. Comment Coverage Analysis

- Coverage: Medium
- Inspected evidence: public logic types、关键安全/并发/迁移注释。
- Exclusions / limits: 未逐符号统计 doc comment。

安全边界、兼容 runner 和迁移原因有较好注释；应避免用 `#3/#5/#12` 这类失去 issue 上下文后难以理解的编号注释。

## 30. Principles Compliance

### Principles Violated

| Principle | Violations | Severity | Affected Areas |
|-----------|------------|----------|----------------|
| Single Responsibility (1.1) | 多个 500+ 行 orchestration/UI 文件 | Medium | AppDelegate、UpdateChecker、RoutingDiagnostics |
| No Hidden Side Effects (5.3) | persistence 失败不暴露 | Medium | AppSettingsHistory |
| Dependency Rule (7.1) | 41 symlink 双 module 类型 | Medium | SnapAI/SnapAILogic |
| Test Behavior / Authenticity (8.1) | 手写注册漏测 | Medium | SnapAILogicTests |

### Principles Respected

- 外部输入普遍有 sanitize/clamp。
- SQLite 写操作本身使用 transaction。
- 网络请求具备 timeout 和传输边界。
- 图片、历史、token 和诊断文本有明确上限。
- updater 具备签名、hash、bundle id 和 designated requirement 验证。

## 31. Architecture Analysis

| Subtype | Count | Affected Areas | Recommended Action |
|---------|-------|----------------|-------------------|
| ModuleBoundary | 1 | 41 symlink | 按 cluster 迁移 |
| DependencyDirection | 1 | app-local model / logic API | DTO/port 后迁移 |
| StateOwnership | 1 | history memory vs SQLite | repository 单一提交点 |
| BoundaryContract | 1 | history mutation result | 返回明确 outcome |
| EvolutionRisk | 1 | 手写 test registry | 自动门禁/自动发现 |

## 32. Documentation Summary

| Subtype | Count | Affected Docs | Recommended Action |
|---------|-------|---------------|-------------------|
| UserDocs | 1 | README/SVG | 更新或去版本化 |
| OperatorDocs | 0 | preflight docs | 保持 |
| DeveloperDocs | 1 | LICENSE 缺失 | 增加许可证与链接 |
| ApiDocs | 0 | URL Scheme/配置 | 保持 |
| DecisionRecord | 0 | migration plan | 保持 |
| StaleDocs | 1 | snapai-ui-overview.svg | 修复 |

## 33. Recommended Fix Order

### Fix Immediately

- 修复 logic suite 漏注册的隐私测试，并增加注册完整性门禁。
- 修复历史 mutation 的持久化失败语义。

### Fix Before Stable Release

- 优化打字机增量渲染。
- 为截图增加 single-flight/in-progress 状态。
- 补充 LICENSE 并更新 README/SVG。

### Schedule Later

- 按 cluster 持续清除 41 个 symlink。
- 拆分 500+ 行 UI/orchestration 文件。
- 用 Instruments/ETTrace 建立 UI 性能基线。

### Ignore for Now

- 不引入额外第三方状态管理或 dependency；当前问题可用本地小改动解决。

## 34. Quick Wins

- 在 runAllLogicTests 增加漏掉的 test 调用。
- 加脚本对比 test 声明与注册清单。
- 为 5 个 icon-only 控件增加动态 accessibility label。
- 将 UI 总览资产改为无版本标题，减少每次 patch release 的文档漂移。
- 截图按钮显示 ProgressView 并在任务期间 disabled。

## 35. Long-term Refactor Plan

1. 先建立可测试的 HistoryMutationOutcome，消除 UI/SQLite 状态分叉。
2. 将 typewriter 推进逻辑迁到 SnapAILogic，使用保存的 String.Index 或 chunk queue。
3. 以 `SettingsTypes/Provider/Action/History` 为核心定义稳定 DTO，按依赖闭包迁移 symlink cluster。
4. 将 AppDelegate 继续收缩为生命周期与 coordinator，业务命令留在 logic/service 层。
5. 每次迁移都执行 declaration/registry gate、logic tests、swift build、macOS smoke 和 release preflight。
