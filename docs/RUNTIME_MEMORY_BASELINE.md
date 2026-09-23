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

## 2.0.6 基线(设置窗口 Liquid Glass 收尾后)

测量环境:Apple Silicon、macOS 27.2、release 配置 + 本地签名构建、
`scripts/run-ui-preview.sh <surface> light` 启动的隔离预览进程
(`com.snapai.preview` 独立 UserDefaults suite,预览假数据 1 供应商 / 4 条历史),
启动后静置约 10 秒再用 `scripts/profile-runtime-memory.sh <pid> <label>` 采样。
footprint 数值含 SwiftUI 渲染树与窗口材质,不同设备与系统版本下仅可同条件对比。

| 场景 | Physical footprint | Peak | RSS | 观察 |
| --- | ---: | ---: | ---: | --- |
| 设置窗口打开(AI 模型页) | 50 MB | 51 MB | 约 130 MB | 全量设置树 + 侧栏 behind-window 材质 |
| 快捷提问面板 | 27 MB | 27 MB | 约 105 MB | 最轻的输入面板 |
| 历史窗口(4 条预览数据) | 40 MB | 40 MB | 约 128 MB | 双栏 + Markdown 渲染 |

与 1.6.55 对比:设置窗口初次显示 48–50 MB → 50 MB,基本持平;
关闭窗口释放 hosting controller 的生命周期策略(1.6.56 节)保持不变,
2.0.6 未引入新的常驻分配。
