# SnapAI 1.6.2

SnapAI 1.6.2 是一次跨应用选区捕获与工程维护补丁版本,重点继续修复右键 Services 触发动作时偶发“未检测到选中文本”的场景,并把逻辑测试拆成更清晰的领域文件。

## 修复与优化

- 增强 Services fallback:当系统 Services pasteboard 没有传入可用文本时,SnapAI 会保留服务调用瞬间识别到的目标应用,避免之后前台 App 变化导致捕获目标漂移。
- 剪贴板兜底前支持强制收起右键菜单等临时 UI,减少菜单仍处于打开状态时拦截 `Command + C` 的情况。
- 保持普通快捷键触发路径的原有策略,只有 Services fallback 会启用更强的临时 UI 收起逻辑。
- 清理设置页旧版 AI 路由布局残留,保留“当前模型摘要 + 路由策略行 + 可展开诊断”的更紧凑结构。
- 逻辑测试从单个巨型 `main.swift` 拆分为更新器、写回/捕获、路由、隐私、命令、设置迁移和历史等领域文件,后续定位回归更直接。

## 更新安全

- 正式 release 构建继续要求稳定自签名证书,不会回退到 ad-hoc 签名。
- 应用内更新继续要求下载并验证 `snapai-manifest-vX.X.X.json` 与 `snapai-manifest-vX.X.X.json.sig`。
- Manifest 内记录 bundle id、designated requirement、证书指纹和 zip SHA256;应用先验签 manifest,再信任其中的更新包校验信息。

## 验证

- `./scripts/run-logic-tests.sh`
- `swift build`
- `plutil -lint Resources/Info.plist`
- `git diff --check`

