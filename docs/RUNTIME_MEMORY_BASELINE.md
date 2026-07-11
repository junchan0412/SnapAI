# SnapAI 运行时内存基线

## 测量入口

先以 release 配置构建并启动:

```bash
./script/build_and_run.sh --verify
```

记录当前场景:

```bash
scripts/profile-runtime-memory.sh SnapAI settings-open
scripts/profile-runtime-memory.sh SnapAI quick-input
```

脚本统一输出 RSS、CPU、physical footprint、peak footprint,以及 `CoreAnimation`、`Image IO`、`Malloc Large`、`Malloc Small` 等重点 VM region。

## 1.6.55 基线

测量环境:Apple Silicon、macOS 27 开发版、本地 release 签名构建。

| 场景 | Physical footprint | Peak | 观察 |
| --- | ---: | ---: | --- |
| 设置窗口初次显示 | 48–50 MB | 56–58 MB | 默认 malloc 实际驻留约 8–10 MB |
| 关闭设置窗口后的旧实现 | 约 81 MB | 约 81 MB | coordinator 与 window 继续保留完整 SwiftUI 设置树 |

绝对数值会受系统 framework cache、窗口内容和调试工具影响,主要用于同一设备、同一构建方式下的前后对比。

## 1.6.56 生命周期策略

- `WindowCoordinator` 复用轻量 `NSWindow` shell。
- 窗口关闭完成后的下一轮主线程把 `contentViewController` 设为 `nil`,释放 SwiftUI hierarchy。
- 重新打开时按当前 section、pin state 和 settings 延迟创建新的 hosting controller。
- 不使用 `isReleasedWhenClosed = true`;实测该模式在 Accessibility 触发关闭时会进入 AppKit/Objective-C 双重 release 崩溃路径。
- macOS smoke 直接验证 reusable window 关闭后 content controller 被清空且进程保持正常。

## 后续基线

- 菜单栏空闲态长期驻留。
- 快捷提问空白、文本输入、图片附件和移除后的峰值。
- 历史窗口大数据量滚动。
- ResultView 流式输出与 Markdown 渲染。
- `UpdateChecker` 下载、解压和替换阶段。
