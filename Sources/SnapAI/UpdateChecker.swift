import AppKit
import Foundation

enum UpdateChecker {
    private static let latestReleaseURL = URL(string: "https://api.github.com/repos/junchan0412/SnapAI/releases/latest")!

    struct Release: Decodable {
        let tagName: String
        let name: String?
        let htmlURL: URL

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name
            case htmlURL = "html_url"
        }
    }

    static func check(presenting window: NSWindow? = nil) {
        Task {
            do {
                let release = try await latestRelease()
                await MainActor.run {
                    presentResult(release, window: window)
                }
            } catch {
                await MainActor.run {
                    presentError(error, window: window)
                }
            }
        }
    }

    private static func latestRelease() async throws -> Release {
        var request = URLRequest(url: latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 12

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw NSError(
                domain: "SnapAI.UpdateChecker",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "GitHub Releases 暂不可用(status \(http.statusCode))。"]
            )
        }
        return try JSONDecoder().decode(Release.self, from: data)
    }

    private static func presentResult(_ release: Release, window: NSWindow?) {
        let current = currentVersion
        let latest = normalizedVersion(release.tagName)
        let hasUpdate = compareVersions(latest, current) == .orderedDescending

        let alert = NSAlert()
        alert.messageText = hasUpdate ? "发现新版本 \(release.tagName)" : "SnapAI 已是最新版本"
        alert.informativeText = hasUpdate
            ? "当前版本: \(current)\n最新版本: \(release.tagName)\n\n点击“打开下载页”前往 GitHub Release 下载新版应用。"
            : "当前版本: \(current)\n最新版本: \(release.tagName)"
        alert.alertStyle = hasUpdate ? .informational : .informational
        if hasUpdate {
            alert.addButton(withTitle: "打开下载页")
            alert.addButton(withTitle: "取消")
        } else {
            alert.addButton(withTitle: "好")
        }

        let response = run(alert, window: window)
        if hasUpdate && response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(release.htmlURL)
        }
    }

    private static func presentError(_ error: Error, window: NSWindow?) {
        let alert = NSAlert(error: error)
        alert.messageText = "检查更新失败"
        alert.informativeText = error.localizedDescription
        run(alert, window: window)
    }

    @discardableResult
    private static func run(_ alert: NSAlert, window: NSWindow?) -> NSApplication.ModalResponse {
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal()
    }

    private static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    private static func normalizedVersion(_ version: String) -> String {
        version.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
    }

    private static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let right = rhs.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(left.count, right.count)
        for i in 0..<count {
            let l = i < left.count ? left[i] : 0
            let r = i < right.count ? right[i] : 0
            if l < r { return .orderedAscending }
            if l > r { return .orderedDescending }
        }
        return .orderedSame
    }
}
