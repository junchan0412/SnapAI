# SnapAI 1.6.71

SnapAI 1.6.71 聚焦结果窗口交互稳定性,以及界面与人机交互的统一打磨。本版合并了 PR #20 的 UI 重构与 PR #21 的空选提示 / 失焦行为修复,并完成正式签名发布。

## 结果窗口失焦行为

- 新增设置项「结果窗口失焦行为」,可选自动关闭、生成后保持、始终保持。
- 默认改为「生成后保持」,避免生成中或完成后一点外部就丢失结果。
- 仅「自动关闭」模式注册点外部关闭监听器;Esc、关闭按钮和写回仍可关闭。
- 导出配置时重置为本机无关的默认策略,不把窗口偏好带给其他机器。

## 空选提示与捕获并发

- 「未检测到选中文字」从阻塞式模态 alert 改为结果窗口非模态横幅。
- 文本捕获引入代际令牌,新触发会使未完成的旧捕获回调失效。
- 已有动作在流式生成时,过期空选回调不会再弹提示或污染上次取词诊断。
- 瞬时提示支持自动消失和手动关闭,不再抢焦点阻塞后续操作。

## 界面与交互统一

- 结果页、历史、设置、快捷提问、权限健康等面板继续收敛到共享 UI 组件。
- 快捷键录制、导入导出、Diff 预览和命令面板的控件与反馈样式更一致。
- 保留已有复制 / 导出 coordinator 与页面级 feedback 通道,不引入按 code block 放大的状态对象。

## 验证

- `scripts/run-audit-remediation-check.sh`
- `scripts/run-logic-tests.sh`
- `scripts/check-logic-symlinks.sh`
- `swift build`
- `scripts/run-macos-smoke-tests.sh --skip-logic`
- 签名 `scripts/preflight-release.sh`

## Release 资产

- `SnapAI-v1.6.71.zip`
- `snapai-manifest-v1.6.71.json`
- `snapai-manifest-v1.6.71.json.sig`
- `snapai-sbom-v1.6.71.json`
