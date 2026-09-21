# SnapAI 1.6.0 迭代报告

## 目标

1.6.0 的目标是对 SnapAI 的核心体验做深度优化:用户在任意应用中选中文字后, SnapAI 应尽量可靠地捕获文本、理解粗粒度来源上下文、选择合适动作和模型,并在需要时安全替换或追加回原应用。

## 已完成

### 1. 文本捕获结构化

- 新增 `TextCaptureOutcome`,把捕获结果从单一字符串升级为结构化状态。
- 记录捕获方式:Accessibility 直读或剪贴板兜底。
- 记录失败原因:Accessibility 空选区、剪贴板快照不安全、复制后剪贴板未更新、复制结果为空。
- 记录剪贴板保护原因和复制等待次数,便于定位“选中了但没有反应”的具体原因。
- 原有 `TextCapture.capture` 保持兼容,新增 `captureDetailed` 给主链路使用。

### 2. 权限健康和请求诊断增强

- `TextCaptureDiagnostic` 新增捕获方式、失败原因、剪贴板保护原因和等待次数。
- 权限健康中心可继续显示最近一次文本捕获状态,但信息更适合排查跨应用兼容问题。
- 请求 pipeline 诊断新增捕获路径和选区来源类型,与隐私、输出和模型策略放在同一组摘要里。

### 3. 选区来源上下文

- 新增 `SelectionSourceContext`,按前台应用名称归类来源类型。
- 支持浏览器、代码编辑器、终端、文档编辑器、聊天工具、邮件客户端、PDF/文档阅读器和未知应用。
- 发送给 AI 的只是粗粒度来源类型和语境提示,不包含窗口标题、文件路径或具体应用名。
- 诊断中的应用名会走 `MarkdownExportSafety` 和敏感信息清洗,避免泄漏 key-like 字符串。

### 4. 主链路接入

- `AppDelegate.triggerAction` 改用结构化捕获结果。
- 捕获成功后,结果面板请求会带上捕获方式和选区来源上下文。
- `ResultViewModel` 在首条 user 消息中加入非敏感来源提示,提升代码、终端日志、网页片段、邮件和聊天文本的理解质量。
- `ActionPipelineDiagnostic` 支持记录 `capture-*` 和 `source-*` 输入策略。

### 5. 全量审查与测试

- 复查主链路相关文件:`AppDelegate`, `TextCapture`, `TextEditTransaction`, `ResultViewModel`, `ActionPipeline`, `TextCaptureDiagnostic`, `PrivacySubmissionPreview`, `AIRequestRouter`。
- 确认既有保护仍在:AX 优先、剪贴板快照、写回前 Diff、替换/追加剪贴板保护、写回失败诊断、上下文包合并、隐私预览和高风险历史保护。
- 新增测试覆盖:
  - 结构化捕获结果保留选区空白。
  - 捕获诊断显示剪贴板兜底和剪贴板保护原因。
  - 选区来源上下文分类常见应用。
  - 来源提示不发送具体应用名。
  - pipeline 记录捕获方式和来源类型。

## 验证计划

- `git diff --check`
- `scripts/run-logic-tests.sh`
- `swift build`
- `scripts/preflight-release.sh`

## 维护建议

- 后续可继续增加按应用的捕获策略,例如对浏览器、终端、代码编辑器、PDF 阅读器分别优化恢复建议。
- 若未来引入窗口标题或文档路径上下文,应默认关闭或在发送前预览中明确展示,避免隐私边界变模糊。
- 可把 `SelectionSourceContext` 扩展为用户可编辑规则,让高级用户自定义应用分类和 Prompt 提示。
