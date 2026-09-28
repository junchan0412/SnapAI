# SnapAI 运行时内存基线

## 测量入口

以 release 配置构建(debug 与 release 数值不可比):

```bash
SNAPAI_RELEASE=1 ./build.sh --release
```

按场景采样:

```bash
scripts/profile-runtime-memory.sh SnapAI settings-open     # 已启动进程的快照
scripts/profile-runtime-memory.sh <pid> <label>            # 指定 pid
scripts/profile-settings-sections.sh                       # 设置窗口 6 个 section 逐个起隔离进程采样
```

隔离预览面(独立 UserDefaults,不碰本机设置)按 surface 起进程,再采样:

```bash
scripts/run-ui-preview.sh <surface> light|dark [--compact]   # surface 见 scripts/run-ui-preview.sh / AppPreview
scripts/profile-runtime-memory.sh <pid> <label>
```

冷启动耗时不是内存,但同属性能基线,见 `docs/STARTUP_BASELINE.md`
(`scripts/measure-startup.sh`)。

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

## 设置窗口按 section 分布(2.0.7)

测量方式:`scripts/profile-settings-sections.sh [等待秒]` —— 每个 section 用
`scripts/run-ui-preview.sh <surface> light` 起一个隔离预览进程(独立 UserDefaults
suite),静置后用 `footprint` 采样 physical footprint / peak / RSS。同一台机器、
同一构建方式下才可对比。

| section | 改造前 | 改造后 | 观察 |
| --- | ---: | ---: | --- |
| 通用(General) | 63 MB | 46 MB | 一页 7 个子区块,改 `LazyVStack` 后屏外子区块不再构建 |
| 模型(默认页) | 47 MB | 47 MB | 内容一屏内装得下,懒加载无收益 |
| 动作(Actions) | 42 MB | 42 MB | 本来就是 `LazyVStack` |
| 历史设置 | 38 MB | 38 MB | 本来就是 `LazyVStack` |
| 供应商(Provider) | 35 MB | 36 MB | 内容在首屏,懒加载无收益(差异在测量噪声内) |
| 权限(Permission) | 32 MB | 32 MB | 内容在首屏,懒加载无收益 |

三条结论:

1. **detail section 是按需构建的**。`SettingsView.selectedSectionContent` 用
   `switch navigation.selectedSection` 只构建当前选中分支,6 个 section 的
   footprint 落在 32–63 MB 且互不相同 —— 若切换前全量构建,数值应当基本一致。
2. **真正的大头是内容本身**。`GeneralSettingsSection` 一页堆了 7 个子区块,
   屏外内容也被构建;改 `LazyVStack`(与 `ActionSettingsSection`、
   `HistorySettingsSection` 既有写法一致)后 63 MB → 46 MB。
3. **默认页(模型)比供应商页贵约 12 MB,不是懒加载问题**。逐块消融实测:
   去掉 `aiOverviewCard` 后 48 → 40 MB,其中 `routingPolicyRow`(1 个 menu
   `Picker` + 2 个 `switch`)去掉后 48 → 42 MB。差值来自控件与卡片材质本身,
   属于产品形态成本,没有靠删 UI 换内存。

窗口关闭后 `WindowCoordinator` 仍在下一轮主线程清空 `contentViewController`
(1.6.56 策略),因此这些数值只在窗口打开期间存在,不是常驻成本。

## 菜单栏空闲态长期驻留(2.0.7)

用真实 release 二进制的隔离启动路径(`SNAPAI_LAUNCH_SMOKE_DIRECTORY` +
`--release-smoke`,不碰本机设置、不弹引导窗口)启动,静置期间按时间点采样:

| 时点 | Physical footprint | Peak | RSS |
| --- | ---: | ---: | ---: |
| +5s | 48 MB | 55 MB | 126 MB |
| +30s | 48 MB | 55 MB | 126 MB |
| +60s | 48 MB | 55 MB | 76 MB |
| +120s | 48 MB | 55 MB | 76 MB |
| +180s | 48 MB | 55 MB | 76 MB |
| +300s | 48 MB | 55 MB | 77 MB |

结论:**5 分钟空闲 footprint 稳定在 48 MB,没有随时间增长**;RSS 从 126 MB
回落到约 76 MB 是未触及页被系统换出,不是泄漏。峰值 55 MB 出现在启动阶段。
隔离路径不注册全局热键与 Services 提供者,这两项是瞬时装配,不改变稳态占用。

## 流式输出峰值(2.0.7)

预览面 `--preview result-stream`:按 token 分片把约 3.7k 字的 Markdown 示例
文档推进结果窗口,覆盖约 16 秒,走真实 `ResultViewModel` 输出路径
(`isStreaming` 置位、`output` 增长、每片触发 Markdown 重渲染)。

| 时点 | Physical footprint |
| --- | ---: |
| t+7s | 38 MB |
| t+11s(推进中) | **49 MB** |
| t+13s 及以后(流结束) | 42–44 MB |
| 进程 `phys_footprint_peak` | **58 MB** |

结论:流式期间最高采到 49 MB、进程峰值 58 MB,流结束后回落到约 44 MB 并稳定 ——
输出缓冲与 Markdown 渲染树在流结束后没有继续累积。

## 更新窗口与下载阶段(2.0.7)

| 场景 | Physical footprint | Peak |
| --- | ---: | ---: |
| 更新窗口(下载进度态,`--preview update-progress`) | 27 MB | 28 MB |

下载本身不进本进程 footprint:zip 由 `URLSessionDownloadTask`
(`UpdateProgressDownloader`)直接落盘临时文件,按字节回报进度,进程内不持有
整包;manifest 与签名是小 JSON(`URLSession.data`);解压走 `/usr/bin/ditto`
子进程,替换走 `/usr/bin/ditto` 脚本 —— 子进程内存不计入本进程。

## 仍未覆盖的场景

- 快捷提问的图片附件添加/移除峰值(需要带图片的预览夹具);
- 历史窗口大数据量(数千条)滚动峰值(需要可注入的历史夹具)。

已覆盖:设置窗口按 section 分布、菜单栏空闲长期驻留、流式输出峰值、
更新窗口与下载阶段、快捷提问面板(2.0.6 节)、历史窗口(2.0.6 节)。

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
