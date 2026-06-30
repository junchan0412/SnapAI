import Foundation

enum InstallLogCommand {
    static let missingSubtitle = "暂无安装日志,将打开权限健康中心"

    static func subtitle(for url: URL?) -> String {
        guard let url else { return missingSubtitle }
        return PermissionHealthSnapshot.shareablePath(url.path)
    }

    static func subtitle(for status: UpdateChecker.InstallLogStatus) -> String {
        switch status {
        case .noRecord:
            return missingSubtitle
        case .untrustedLocation(let path):
            return "安装日志路径不受信任:\(PermissionHealthSnapshot.shareablePath(path))"
        case .missing(let path):
            return "安装日志已过期:\(PermissionHealthSnapshot.shareablePath(path))"
        case .available(let url):
            return subtitle(for: url)
        }
    }
}
