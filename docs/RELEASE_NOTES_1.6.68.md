# SnapAI 1.6.68

SnapAI 1.6.68 聚焦结果操作的可见性与失败恢复。此前复制结果、复制 Markdown 和复制诊断会直接清空并写入系统剪贴板，却不检查写入结果；对话导出使用 `try?`,保存失败时用户得不到任何提示。

## 操作反馈

- 新增真实 logic 源码 `ResultOperationFeedback`。
- success 与 warning 使用稳定语义、图标和不同停留时长。
- 每次操作生成独立 event ID，连续执行相同复制命令仍会重新显示提示。
- footer 新增紧凑反馈条，成功使用绿色、失败使用橙色。
- 提示支持手动关闭，并在成功约 2.2 秒、失败约 4.5 秒后自动消失。
- 反馈条包含 accessibility label 和明确的关闭按钮标签。

## Result operation coordinator

- 新增 app 层 `ResultOperationCoordinator`。
- 统一结果、Markdown、精简诊断和完整诊断的 pasteboard 写入。
- 检查 `setString` 返回值，写入失败时显示可操作提示。
- 统一替换/追加 handler 适配，VM 不再直接调用 writeback coordinator。
- 导出改为显式 `do/catch`，成功显示文件名，失败显示已脱敏的错误原因。
- 用户取消 Save Panel 不显示错误，保持安静取消语义。

## 安全导出文件名

- 新增 `ResultExportFilename`。
- 清理动作名中的 `/`、`\\`、`:` 和控制字符。
- 连续分隔符合并，空动作名回退为 `SnapAI`。
- 用户可控 stem 限制为 64 个字符，负 timestamp 归零。

## Observation 与架构

- feedback 状态位于 coordinator 自己的 `@Published` leaf。
- `ResultOperationFeedbackHost` 只观察 coordinator，不把提示状态发布到根 `ResultViewModel`。
- `ResultViewModel` 保持 535 行，同时移除 AppKit import、pasteboard mutation、Save Panel 和静默文件写入。
- operation coordinator 75 行，feedback view 63 行。
- `SnapAILogic` 真实源码从 45 增至 46，symlink 保持 36 个。

## 验证

- 新增 feedback kind、图标、停留时长、重复 event ID 与安全文件名测试。
- remediation gate 禁止 pasteboard/save panel/静默写入回流 VM，并保护独立 feedback observer。
- logic suite、SwiftPM build、macOS smoke 与签名 release preflight 均纳入发布验证。

## Release 资产

- `SnapAI-v1.6.68.zip`
- `snapai-manifest-v1.6.68.json`
- `snapai-manifest-v1.6.68.json.sig`
- `snapai-sbom-v1.6.68.json`
