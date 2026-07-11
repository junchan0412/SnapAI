# SnapAI 1.6.65 迭代报告

## 问题定位

旧 `runStream` 在 route execution 前执行七类准备工作:

1. 根据最终 messages 刷新 privacy payload counts。
2. 读取 active context summary。
3. 统计 message characters、estimated tokens 和 image attachments。
4. 构造 action pipeline diagnostic。
5. 获取 routing metrics snapshot。
6. 选择 candidate routes。
7. 构造正常或无候选 diagnostics。

这使 VM 同时知道 privacy、context、payload、routing 和恢复提示的内部细节。

## Preparation outcome

`ResultRequestPreparationInput` 固化 preparation 所需输入。coordinator 返回:

- `ready`:routes、diagnostics 和更新后的 privacy。
- `unavailable`:用户消息、完整 diagnostics 和更新后的 privacy。

VM 无论成功还是失败都先接收 privacy snapshot,再推进 route 或显示错误,避免部分状态更新。

## 一致性

同一个 `payloadDiagnostic` 同时驱动 route routingTextCharacterCount 和诊断输出;同一个 `requestHasImage` 同时驱动 capability selection 与 diagnostics,防止两个路径各自重新推导后产生偏差。

## 结果

- VM preparation helper/diagnostic factory/candidate selector:移出 coordinator。
- `ResultViewModel`:664 → 626 行。
- coordinator:111 行。
- logic target 保持 44 个真实源码、36 个 symlink。
- logic suite、SwiftPM build、macOS smoke 与 remediation gate 通过。

本轮没有修改 provider payload 内容或网络协议,未触发真实第三方请求。
