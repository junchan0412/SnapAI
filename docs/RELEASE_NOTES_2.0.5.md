# SnapAI 2.0.5

SnapAI 2.0.5 把 AI 相关设置拆成两个独立页面，并修复 Anthropic 原生协议的配置链路。功能、配置、快捷键与历史记录完全兼容 2.0.x。

## 设置页拆分：AI 模型 / AI 供应商

- 侧栏“工作空间”新增 **AI 供应商**（`network` 图标），原 **AI 模型** 页只保留当前工作模型、路由策略与 Temperature。
  - AI 模型页：`Sources/SnapAI/ModelSettingsSection.swift`（新增）——当前工作模型卡、供应商/模型切换菜单、自动路由与 fallback、路由诊断、Temperature。
  - AI 供应商页：`Sources/SnapAI/ProviderSettingsSection.swift`（瘦身）——供应商总览卡（`n/m 可请求` + 待处理项点名）、供应商卡片（连接分组、拉取模型、测试连接、高级参数）。
- 新分区 `SettingsSection.model / .provider`（`Sources/SnapAILogic/SettingsSection.swift`），旧 `ai` 通过 `resolvingLegacy` 兼容映射到模型页。
- 深链兼容：`snapai://settings/ai` 仍打开模型页（自动化层映射），新增 `snapai://settings/provider`；命令面板新增“打开 AI 供应商设置”条目；权限健康中心的“打开 AI 设置”指向供应商页（API Key / AI 请求本就是供应商配置问题）。

## Anthropic 配置修复

- **Key 前后空白自动忽略**：粘贴 Key 常带空格/换行，Anthropic 服务端不忽略空格（实测返回 401 invalid，与无 key 的 `x-api-key header is required` 不同，证明头与路径正确、问题只在 key 本身）。`Settings.apiKey` 访问层统一 trim，测试连接 / 拉取模型 / 流式请求与就绪检查全部受益；存储层保留原文。获取模型与测试连接按钮的禁用判断同步改为 trim 后判空。
- **协议专属引导**：Anthropic 协议下端点占位显示 `https://api.anthropic.com/v1`，并提示“Key 通过 x-api-key 发送（前后空格会自动忽略）”；API Key 占位显示 `sk-ant-…`。
- **就绪状态行**：每个供应商卡片的连接分组新增“状态”行，直接复用请求层 `AIRequestRouter.providerReadiness`（与真实请求能力一致），未就绪时显示 `displayText + recoverySuggestion`。
- 经真实端点验证：`GET /v1/models` 与 `POST /v1/messages` 在错误 key 下均返回标准 `authentication_error`，确认 `normalizedBase` 追加 `/v1`、方法路径剥离与 `x-api-key + anthropic-version` 头组合正确。

## 视觉验证

- 深色 AI 模型页：当前工作模型卡 + Temperature，下方无供应商列表。
- 深色 AI 供应商页：供应商总览卡（`1/1 可请求`）+ OpenAI 卡片折叠态。
- 浅色 AI 供应商页：总览卡与供应商卡回退渲染正常。
- 截图：`docs/screenshots/snapai-model-dark.png`、`snapai-provider-dark.png`、`snapai-provider-light.png`。

## 兼容性

- 最低系统版本保持 macOS 14；Liquid Glass 与 2.0.4 一致（26+ 生效，低版本回退）。
- 不改变更新包的下载、校验与安装安全链路；manifest 公钥、bundle id、签名连续性校验保持不变。
- 提供 ZIP、签名 manifest、签名文件与 SBOM。应用仍采用自签名分发，尚无 Apple notarization；首次安装步骤见 README。

## 已知事项

- 无。preflight 全绿后发布。
