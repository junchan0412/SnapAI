import AppKit
import Foundation
import Sparkle

/// 更新通道:Sparkle(appcast + EdDSA 签名 + 标准更新窗口)。
///
/// 迁移说明:
/// - 通道:`SUFeedURL` 指向 `releases/latest/download/appcast.xml`,
///   由 `scripts/generate-appcast.sh` 在发版时生成并签名;
/// - 完整性:appcast 里的 zip 带 EdDSA 签名(`SUPublicEDKey` 在 Info.plist),
///   Sparkle 还会校验新应用与已装应用的代码签名连续性 —— 自签名身份
///   (证书指纹固定)满足该要求,无需 Apple 公证;
/// - UI:用 Sparkle 标准更新窗口(发布说明、下载进度、安装并重启),
///   不再自研 UpdateWindow / 下载器 / 替换脚本;
/// - 自动检查保持关闭(`SUEnableAutomaticChecks=false`),仍由用户点
///   「检查更新…」触发,与迁移前行为一致。
///
/// 只暴露 `check()`,菜单、命令面板与自动化深链的调用点不变。
@MainActor
enum UpdateCheckerApp {
    /// 懒加载:首次发起检查才构造 updater,避免启动期做任何网络动作。
    private static let controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    static func check() {
        controller.checkForUpdates(nil)
    }

    /// 当前是否可以发起检查(检查进行中时为 false,避免重复触发)。
    static var canCheckForUpdates: Bool {
        controller.updater.canCheckForUpdates
    }

    /// 启动即装配 updater(自动检查关闭,仅完成配置校验与 feed 解析准备)。
    static func start() {
        _ = controller
    }
}
