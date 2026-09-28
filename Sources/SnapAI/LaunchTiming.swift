import Darwin
import Foundation

/// 启动耗时打点:`exec` → `main` 入口 → `applicationDidFinishLaunching` 结束。
///
/// 菜单栏常驻应用对冷启动延迟敏感,此前只有内存基线、没有时间基线。
/// 三个时刻的来源:
/// - `exec`:`sysctl(KERN_PROC_PID)` 的 `p_starttime`(进程创建墙钟,含 dyld);
/// - `main`:`main.swift` 顶部显式打点(动态链接与全局初始化之后);
/// - 就绪:`LaunchCoordinator.didFinishLaunching` 的 defer,覆盖 smoke 早退分支。
///
/// 只做一次性墙钟打点,不引入依赖、不做采样统计;聚合与中位数由
/// `scripts/measure-startup.sh` 在进程外完成,结果见 docs/STARTUP_BASELINE.md。
enum LaunchTiming {
    /// CFAbsoluteTime 与 Unix 纪元的差值(秒)。
    private static let unixEpochOffset: Double = 978_307_200

    private static let processStart: Double? = LaunchTiming.readProcessStart()
    private static var mainEntry: Double?
    private static var reported = false

    static func markMainEntry() {
        guard mainEntry == nil else { return }
        mainEntry = CFAbsoluteTimeGetCurrent()
    }

    static func markReady() {
        guard !reported else { return }
        reported = true
        let ready = CFAbsoluteTimeGetCurrent()
        let mainEntry = mainEntry ?? ready
        guard let processStart else {
            fputs(String(format: "SnapAI launch: main->ready %.0f ms\n",
                         (ready - mainEntry) * 1_000), stderr)
            return
        }
        let execToReady = (ready - processStart + unixEpochOffset) * 1_000
        let dyldToMain = (mainEntry - processStart + unixEpochOffset) * 1_000
        let assembly = (ready - mainEntry) * 1_000
        fputs(String(format: "SnapAI launch: exec->ready %.0f ms (dyld+init %.0f ms, assembly %.0f ms)\n",
                     execToReady, dyldToMain, assembly), stderr)
    }

    /// 进程创建时刻(Unix epoch 秒)。失败返回 nil,报告降级为 main→ready。
    private static func readProcessStart() -> Double? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0 else { return nil }
        let start = info.kp_proc.p_starttime
        let seconds = Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000
        return seconds > 0 ? seconds : nil
    }
}
