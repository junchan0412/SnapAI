# SnapAI 1.6.70

SnapAI 1.6.70 聚焦历史记录与 Markdown code block 的复制、导出可靠性。此前历史窗口直接操作系统剪贴板且忽略写入结果，Markdown 导出使用 `try?` 静默吞掉文件系统错误；设置页历史复制和 code block 复制也没有明确成功或失败反馈。

## 历史复制与导出

- 历史窗口的单条结果、完整记录和当前筛选复制统一通过 `ResultOperationCoordinator`。
- 每次剪贴板写入都会检查 `NSPasteboard.setString` 返回值。
- 当前筛选复制成功后显示实际记录数量。
- Markdown 导出复用原子写入、错误捕获与敏感错误文本脱敏逻辑。
- 导出文件名复用 `ResultExportFilename`,统一移除路径分隔符、控制字符并限制长度。
- 用户取消 Save Panel 时不显示错误或成功提示。

## 更清晰的 UX 反馈

- 历史窗口新增页面级 success/warning banner,支持手动关闭和按结果类型自动消失。
- 历史设置页复制结果使用相同反馈语义。
- 单条结果、完整记录、筛选集合和代码块使用可区分的成功文案。
- 剪贴板失败时提示检查权限后重试；文件写入失败时展示经过脱敏与长度限制的原因。

## Markdown code block

- code block 复制按钮不再直接访问 `NSPasteboard`。
- 复制动作沿 `MarkdownView` → `ResultOutputDisplay` → `ResultViewModel` 路由到现有 coordinator。
- 反馈继续由结果页 footer 的 leaf observer 展示。
- 没有为每个 code block 创建 coordinator、timer 或 observable object,避免长回答按代码块数量放大状态与内存占用。

## 冗余与门禁

- 删除历史窗口和历史设置页重复的 pasteboard mutation。
- 删除历史窗口静默 `try? write` 路径与重复 Save Panel 实现。
- remediation gate 新增历史窗口、历史设置和 Markdown view 的 direct pasteboard 禁止项。
- remediation gate 明确禁止历史导出重新引入静默写入失败。
- 安全文件名测试新增历史导出回归样例。

## 验证

- `scripts/run-audit-remediation-check.sh`
- `scripts/run-logic-tests.sh`
- `scripts/check-logic-symlinks.sh`
- `swift build`
- `scripts/run-macos-smoke-tests.sh --skip-logic`
- 签名 `scripts/preflight-release.sh`

## Release 资产

- `SnapAI-v1.6.70.zip`
- `snapai-manifest-v1.6.70.json`
- `snapai-manifest-v1.6.70.json.sig`
- `snapai-sbom-v1.6.70.json`
