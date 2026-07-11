# SnapAI 1.6.55

SnapAI 1.6.55 聚焦快捷提问的图片附件性能和 UX。本版消除 SwiftUI 重绘时的重复图片解码,缩短图片压缩中间对象的生命周期,并让成功、失败和移除状态更清晰。

## 性能与内存

- `QuickInputModel` 缓存已优化图片的 `NSImage` preview,界面重绘不再从同一份 `Data` 重复解码。
- 每个图片尺寸/质量候选在独立 `autoreleasepool` 中生成,未采用的 bitmap、PNG 和 JPEG 中间对象可及时释放。
- 发送或移除附件时统一清理编码 data、preview、MIME 和 notice,避免残留已解码图片。
- remediation gate 防止图片预览回退为 SwiftUI body 内 `NSImage(data:)` 重解码。

## UI / UX

- 截图与剪贴板图片统一通过 `attachImage` 更新,避免部分状态成功、部分状态残留。
- 剪贴板没有图片时显示“请先复制图片后再试”,不再静默无响应。
- 图片优化成功使用 checkmark 和普通辅助色;真正失败才使用橙色警告样式。
- 移除附件按钮新增 Help 和 accessibility label。
- 实际 UI 核对覆盖空面板、无图片提示、截图预览、优化状态和移除后发送按钮恢复禁用。

## 验证

- `scripts/run-audit-remediation-check.sh`
- `scripts/run-logic-tests.sh`
- `swift build`
- `scripts/run-macos-smoke-tests.sh --skip-logic`
- `./script/build_and_run.sh --verify`
- 本机 Accessibility UI 交互检查
- `scripts/preflight-release.sh`

## Release 资产

- `SnapAI-v1.6.55.zip`
- `snapai-manifest-v1.6.55.json`
- `snapai-manifest-v1.6.55.json.sig`
- `snapai-sbom-v1.6.55.json`
