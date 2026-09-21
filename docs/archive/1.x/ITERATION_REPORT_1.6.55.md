# SnapAI 1.6.55 迭代报告

## 背景

快捷提问的图片附件以 `Data` 保存,但预览直接在 `QuickInputView.body` 中调用 `NSImage(data:)`。文本输入、截图状态、动作菜单等任意 published state 变化都会触发重绘和重复解码。图片优化还会依次生成多个分辨率、PNG 和 JPEG 候选,这些对象可能累积到外层 autorelease 周期结束。

## 预览缓存

- `QuickInputModel` 新增 `imagePreview`,附件成功时只解码一次。
- SwiftUI view 直接消费缓存 preview,不再读取编码 data。
- `attachImage` 统一更新 data、preview、MIME 和成功 notice。
- `clearImage` 统一释放所有附件状态,供发送完成和用户移除复用。

## 压缩峰值内存

- 每个像素上限候选包裹在独立 `autoreleasepool` 中。
- PNG 和多个 JPEG quality 候选如果未命中限制,会在进入下一档分辨率前释放。
- 最低质量 fallback 也在独立池中执行。

## 交互完善

- 没有剪贴板图片时给出可执行恢复建议。
- 成功 notice 与 warning 使用不同图标和颜色语义。
- 移除按钮具备 Help 与 accessibility label。
- 本机 UI 验证确认附件出现后发送按钮启用,移除后 preview、notice 消失且发送按钮重新禁用。

## 验证结果

- SwiftPM build:通过。
- macOS smoke:通过。
- build-and-run launch verify:通过。
- Accessibility UI 检查:通过。
