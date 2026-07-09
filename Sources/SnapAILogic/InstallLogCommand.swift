import Foundation

public enum InstallLogCommandStatus: Equatable {
    case noRecord
    case untrustedLocation(String)
    case missing(String)
    case available(URL)
}

public enum InstallLogCommand {
    public static let missingSubtitle = "暂无安装日志,将打开权限健康中心"

    public static func subtitle(for url: URL?) -> String {
        guard let url else { return missingSubtitle }
        return shareablePath(url.path)
    }

    public static func subtitle(for status: InstallLogCommandStatus) -> String {
        switch status {
        case .noRecord:
            return missingSubtitle
        case .untrustedLocation(let path):
            return "安装日志路径不受信任:\(shareablePath(path))"
        case .missing(let path):
            return "安装日志已过期:\(shareablePath(path))"
        case .available(let url):
            return subtitle(for: url)
        }
    }

    public static func shareablePath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "none" }

        let home = NSHomeDirectory()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !home.isEmpty {
            let normalizedHome = "/" + home
            if trimmed == normalizedHome {
                return "~"
            }
            if trimmed.hasPrefix(normalizedHome + "/") {
                return "~" + trimmed.dropFirst(normalizedHome.count)
            }
        }

        let components = trimmed.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard components.count >= 3,
              components[0].isEmpty,
              components[1] == "Users",
              !components[2].isEmpty else {
            return trimmed
        }
        return "/" + (["Users", "[user]"] + Array(components.dropFirst(3))).joined(separator: "/")
    }
}
