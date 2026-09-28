# SnapAI 冷启动耗时基线

菜单栏常驻应用的用户对「开机即驻留」的启动延迟敏感;此前只有内存基线,
没有时间基线。本基线用 `CFAbsoluteTime` 打点 + 进程外聚合建立可比对的参照。

## 打点口径

三个时刻,一条 stderr 输出:

| 时刻 | 来源 | 含义 |
| --- | --- | --- |
| `exec` | `sysctl(KERN_PROC_PID).p_starttime` | 进程创建墙钟,含 dyld 与全局初始化 |
| `main` | `main.swift` 第一条语句 `LaunchTiming.markMainEntry()` | 动态链接完成后 |
| 就绪 | `LaunchCoordinator.didFinishLaunching` 的 `defer` | 菜单栏、面板、热键装配完成(覆盖 smoke 早退分支) |

输出形如:

```text
SnapAI launch: exec->ready 182 ms (dyld+init 9 ms, assembly 173 ms)
```

`dyld+init` = `exec → main`,`assembly` = `main → 就绪`。

## 测量方法

```bash
SNAPAI_RELEASE=1 ./build.sh --release   # release + 本地签名构建
scripts/measure-startup.sh 7            # 7 次采样,自动聚合 min/中位数/max
```

脚本用**隔离 HOME** 启动真实二进制:代码路径与正常冷启动一致(不含 launch
smoke 的隔离持久化步骤),又不会改写本机设置或触发 iCloud 同步;每次采样
拿到打点行后立刻结束进程。首次启动会晚 0.3 秒弹引导窗口,在采样点之后,
不影响计时。

## 2.0.7 基线

测量环境:Apple Silicon、macOS 27.2、release 配置 + 本地签名构建、7 次采样。

| 指标 | 数值 |
| --- | ---: |
| exec→就绪 最小 | 172 ms |
| exec→就绪 中位数 | **182 ms** |
| exec→就绪 最大(首次) | 624 ms |
| dyld+init(热) | 8–9 ms |
| assembly(热) | 164–190 ms |

解读:

- **首次启动明显更慢**:同一轮采样的第一次是 624 ms,其中 dyld+init 占
  403 ms —— 页缓存未热、框架按需换入。真实的「开机后第一次驻留」应按这个
  量级预期,而不是中位数。
- **热启动以装配为主**:dyld+init 只有 8–9 ms,170 ms 左右几乎全在
  `applicationDidFinishLaunching` —— 状态栏项、结果面板、命令面板、历史与
  权限窗口、菜单装配、全局热键注册。后续若要继续压缩,优化对象是装配顺序
  (例如把非首屏窗口的创建推迟到首次使用),不是动态链接。
- 数值用于**同一设备、同一构建方式下的前后对比**,跨机器比较无意义。

## 复测注意事项

- 每次改动启动路径(新增窗口、新增观察者、新增权限检查)后复测并更新本表;
- 采样脚本会打印原始行,保留原始行便于回溯;
- 与 `docs/RUNTIME_MEMORY_BASELINE.md` 一样,只在 release 构建上测量。
