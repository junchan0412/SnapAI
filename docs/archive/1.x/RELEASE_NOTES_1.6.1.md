# SnapAI 1.6.1

SnapAI 1.6.1 是一次稳定性与发布链路补丁版本,重点修复跨应用右键服务菜单取词、AI fallback 边界和历史存储写入频率。

## 修复与优化

- 增强 macOS Services 取词:兼容 UTF-8/UTF-16 纯文本、RTF/HTML 与部分旧式 pasteboard 文本类型,减少右键选中文本后提示“未检测到选中文本”的情况。
- 保留 Accessibility 直读和剪贴板兜底路径,并继续在权限健康中心记录捕获方式、失败原因、剪贴板保护原因和恢复建议。
- 调整 AI fallback 策略:hidden thinking 不再阻止自动切换备用模型;只有已经产生用户可见 partial output 时才阻止静默切换。
- 优化设置保存:普通设置修改不再无差别重写历史 SQLite,减少编辑 Prompt、供应商或快捷键时的无谓 I/O。
- README 同步最新安装、更新、签名 manifest、服务菜单和模块结构说明。

## 更新安全

- 正式 release 构建继续要求稳定自签名证书,不会回退到 ad-hoc 签名。
- 应用内更新继续要求下载并验证 `snapai-manifest-vX.X.X.json` 与 `snapai-manifest-vX.X.X.json.sig`。
- Manifest 内记录 bundle id、designated requirement、证书指纹和 zip SHA256;应用先验签 manifest,再信任其中的更新包校验信息。

## 验证

- `./scripts/run-logic-tests.sh`
- `swift build`
- `plutil -lint Resources/Info.plist`
- `git diff --check`
- `scripts/preflight-release.sh --skip-package`
