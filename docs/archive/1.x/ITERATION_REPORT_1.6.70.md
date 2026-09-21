# SnapAI 1.6.70 迭代报告

## 问题证据

历史窗口存在两条与结果页能力重复但可靠性更弱的实现：复制路径直接调用 `clearContents` / `setString` 且忽略返回值，导出路径使用 `try? markdown.write`。因此剪贴板拒绝写入或保存位置不可写时，用户看不到任何结果，也无法区分操作成功、失败或取消。

历史设置页和 Markdown code block 还有各自独立的 pasteboard mutation，形成相同语义的多份实现。它们既没有统一错误文案，也无法复用 v1.6.68 已建立的短暂 feedback 生命周期。

## 统一操作边界

`ResultOperationCoordinator` 新增通用 Markdown export 入口，调用者提供安全建议文件名和空内容文案。原结果页 export API 继续保留，并委托到通用入口；历史窗口因此不再拥有 Save Panel、文件写入或错误格式化逻辑。

历史窗口与历史设置页各自持有一个页面级 coordinator。feedback 仍由 `ResultOperationFeedbackHost` 这一 leaf observer 消费，提示显示、自动消失和手动关闭不会发布到 `HistoryWindowModel`，也不会触发历史筛选、数据库读取或 semantic search。

## Code block 状态与内存

为避免每个 code block 创建独立 `ObservableObject`，复制动作通过 closure 向上路由：`CodeBlockView` 只传递 raw code，`ResultViewModel.copyCodeBlock` 再调用已有页面级 coordinator。无论回答包含一个还是多个代码块，结果窗口仍只有一个操作反馈对象和一条自动消失 task。

这同时删除了 `MarkdownView` 对 AppKit pasteboard 细节的隐式依赖，使它继续保持纯展示组件边界。

## UX 结果

- 复制单条结果、完整记录、筛选集合与 code block 后均有明确成功反馈。
- 筛选集合反馈包含实际条目数。
- 剪贴板失败与文件系统失败不再静默。
- Save Panel 取消仍被视为用户正常退出，不产生干扰提示。
- 历史导出文件名与对话导出使用同一安全规则。

## 回归保护

remediation gate 现在禁止 `HistoryWindow`、`HistorySettingsSection` 和 `MarkdownView` 直接操作 pasteboard，并禁止历史窗口重新出现 `try? write`。logic test 覆盖历史安全文件名；原有 operation feedback、错误停留时长和重复事件 ID 测试继续通过。

本轮没有触发真实 provider streaming，也没有向第三方发送内容。性能结论限定为已删除的重复实现、主模型 invalidation 隔离和逐 code block 状态分配避免，不声明未经过 Instruments 测量的延迟或内存百分比。
