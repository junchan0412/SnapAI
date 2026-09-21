# SnapAI 1.6.68 迭代报告

## 问题定位

结果 toolbar、菜单和 Command Palette 共用 VM 命令，但最终副作用散落在 `ResultViewModel`：

1. 四种复制操作不检查 pasteboard 写入是否成功。
2. 操作成功后没有 UI 确认，用户容易重复点击或切换应用检查剪贴板。
3. Markdown 导出用 `try?` 忽略文件写入错误。
4. 动作名未经 filename 清理直接进入 Save Panel 建议名称。
5. 若把提示直接做成 VM 的 `@Published`,每次复制又会让整个结果窗口参与 invalidation。

## Coordinator 与反馈 leaf

`ResultOperationCoordinator` 现在拥有 AppKit 边界：pasteboard、Save Panel、文件写入以及 writeback handler 适配。它将结果归约为 `ResultOperationFeedback`，并通过自己的 observable state 发布。

`ResultOperationFeedbackHost` 是 footer 中唯一的 observer。根 `ResultView` 仍观察 VM 的业务状态，但操作提示的出现、自动消失或手动关闭只 invalidation 反馈叶子，不会触发 output、source、route 和 follow-up 区域重算。

## 失败恢复

- pasteboard `setString` 失败时提示检查剪贴板权限并重试。
- export 写入使用 `do/catch`，错误文本经过敏感内容清理并限制长度。
- 空内容调用会解释“当前没有可复制/导出的内容”。
- Save Panel cancel 返回 nil，不将用户主动取消误报为失败。

## 文件名边界

`ResultExportFilename` 把动作名视为不可信 filename 输入：移除路径分隔符与控制字符、合并空段、限制长度，并提供 `SnapAI` fallback。测试覆盖负 timestamp、换行、slash、colon、空名称和超长名称。

## 结果

- VM 不再 import AppKit，也不直接访问 pasteboard、Save Panel 或文件写入。
- `ResultViewModel` 保持 535 行。
- operation coordinator:75 行；feedback view:63 行。
- logic target:45 → 46 个真实源码；symlink 保持 36 个。
- build、logic suite 与 remediation gate 首轮通过。

本轮 UI 变化是本地操作反馈，不需要真实 provider 内容；没有触发向第三方发送数据。发布前继续执行 macOS smoke 和签名 preflight。
