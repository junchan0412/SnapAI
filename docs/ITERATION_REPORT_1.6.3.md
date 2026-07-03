# SnapAI 1.6.3 迭代报告

## 目标

1.6.3 延续 1.6.x 的主链路稳定性工作,补齐历史知识库的本地语义搜索能力,并让历史窗口、URL 自动化导出和历史上下文包生成在筛选结果上保持一致。

## 已完成

- 本地语义搜索:新增轻量概念词族匹配,覆盖 Keychain/权限/签名/更新/路由/图片/写回/翻译/润色/上下文等常用问题域。
- 隐私边界:语义匹配完全在本机执行,不引入云端 embedding 或外部索引服务。
- 搜索一致性:历史窗口、历史导出 URL 和“从历史创建上下文包”共用 `HistorySearch.filteredEntries`。
- UI 文案:历史窗口搜索框更新为“搜索历史、语义、原文、结果或模型…”。
- 文档更新:README、Release Notes 和 UI 总览图同步到 1.6.3。

## 风险控制

- 语义搜索只作为 FTS 与原有紧凑匹配的补充,不改变无查询时的筛选行为。
- 动作、模型、标签、收藏筛选仍在最终结果阶段生效,避免语义命中绕过用户筛选。
- 对容易混淆的 `token` 做了收窄处理,避免“首 token 时间”误命中 Keychain/API Key 语义。
- 新增逻辑测试覆盖中文语义查询命中英文历史、路由语义匹配和筛选约束。

## 验证结果

- 逻辑测试通过:`SnapAILogicTests passed`
- SwiftPM 构建通过
- release 预检通过
- `Resources/Info.plist` 语法通过
- `git diff --check` 通过

## 发布包

完整 release 包应包含:

- `SnapAI-v1.6.3.zip`
- `snapai-manifest-v1.6.3.json`
- `snapai-manifest-v1.6.3.json.sig`

