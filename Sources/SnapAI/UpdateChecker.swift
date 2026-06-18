import AppKit
import Foundation

enum UpdateChecker {
    private static let latestReleaseURL = URL(string: "https://api.github.com/repos/junchan0412/SnapAI/releases/latest")!

    struct Release: Decodable {
        let tagName: String
        let name: String?
        let htmlURL: URL
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name
            case htmlURL = "html_url"
            case assets
        }

        var appZipAsset: Asset? {
            assets.first { asset in
                let lower = asset.name.lowercased()
                return lower.hasSuffix(".zip") && lower.contains("snapai")
            }
        }
    }

    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    enum UpdateError: LocalizedError {
        case noInstallAsset
        case downloadFailed(Int)
        case invalidArchive
        case bundleMismatch
        case installLocationNotWritable(String)

        var errorDescription: String? {
            switch self {
            case .noInstallAsset:
                return "未在最新 Release 中找到 SnapAI 的 zip 安装包。"
            case .downloadFailed(let code):
                return "下载更新失败(status \(code))。"
            case .invalidArchive:
                return "更新包无法解压,或其中未找到 SnapAI.app。"
            case .bundleMismatch:
                return "更新包中的应用标识与当前 SnapAI 不一致,已取消安装。"
            case .installLocationNotWritable(let path):
                return "当前安装位置不可写:\n\(path)\n\n请将 SnapAI 放到 /Applications 或 ~/Applications 后重试。"
            }
        }
    }

    static func check() {
        Task {
            do {
                let release = try await latestRelease()
                await MainActor.run {
                    presentResult(release)
                }
            } catch {
                await MainActor.run {
                    presentError(error)
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

    private static func presentResult(_ release: Release) {
        let current = currentVersion
        let latest = normalizedVersion(release.tagName)
        let hasUpdate = compareVersions(latest, current) == .orderedDescending

        let alert = NSAlert()
        alert.messageText = hasUpdate ? "发现新版本 \(release.tagName)" : "SnapAI 已是最新版本"
        alert.informativeText = hasUpdate
            ? "当前版本: \(current)\n最新版本: \(release.tagName)\n\n建议直接安装更新并重启 SnapAI,避免手动下载后覆盖安装。若发布包持续使用同一个稳定签名身份,辅助功能权限通常可保留。"
            : "当前版本: \(current)\n最新版本: \(release.tagName)"
        alert.alertStyle = hasUpdate ? .informational : .informational
        if hasUpdate {
            alert.addButton(withTitle: "安装并重启")
            alert.addButton(withTitle: "打开下载页")
            alert.addButton(withTitle: "取消")
        } else {
            alert.addButton(withTitle: "好")
        }

        let response = run(alert)
        if hasUpdate && response == .alertFirstButtonReturn {
            install(release)
        } else if hasUpdate && response == .alertSecondButtonReturn {
            NSWorkspace.shared.open(release.htmlURL)
        }
    }

    private static func install(_ release: Release) {
        Task {
            do {
                let asset = try installAsset(from: release)
                let zipURL = try await download(asset)
                let newAppURL = try unpackApp(from: zipURL)
                try await MainActor.run {
                    try launchInstaller(newAppURL: newAppURL, releaseTag: release.tagName)
                }
            } catch {
                await MainActor.run {
                    presentInstallError(error, release: release)
                }
            }
        }
    }

    private static func installAsset(from release: Release) throws -> Asset {
        guard let asset = release.appZipAsset else { throw UpdateError.noInstallAsset }
        return asset
    }

    private static func download(_ asset: Asset) async throws -> URL {
        var request = URLRequest(url: asset.browserDownloadURL)
        request.timeoutInterval = 90
        let (temporaryURL, response) = try await URLSession.shared.download(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw UpdateError.downloadFailed(http.statusCode)
        }

        let updateDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SnapAIUpdate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: updateDir, withIntermediateDirectories: true)
        let zipURL = updateDir.appendingPathComponent(asset.name)
        try FileManager.default.moveItem(at: temporaryURL, to: zipURL)
        return zipURL
    }

    private static func unpackApp(from zipURL: URL) throws -> URL {
        let unpackDir = zipURL.deletingLastPathComponent().appendingPathComponent("unpacked", isDirectory: true)
        try FileManager.default.createDirectory(at: unpackDir, withIntermediateDirectories: true)
        try runTool("/usr/bin/ditto", arguments: ["-x", "-k", zipURL.path, unpackDir.path])

        guard let enumerator = FileManager.default.enumerator(
            at: unpackDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw UpdateError.invalidArchive
        }

        for case let url as URL in enumerator where url.lastPathComponent == "SnapAI.app" {
            let infoURL = url.appendingPathComponent("Contents/Info.plist")
            guard let info = NSDictionary(contentsOf: infoURL),
                  let bundleID = info["CFBundleIdentifier"] as? String,
                  bundleID == Bundle.main.bundleIdentifier else {
                throw UpdateError.bundleMismatch
            }
            try runTool("/usr/bin/codesign", arguments: ["--verify", "--deep", "--strict", url.path])
            return url
        }
        throw UpdateError.invalidArchive
    }

    @MainActor
    private static func launchInstaller(newAppURL: URL, releaseTag: String) throws {
        let currentAppURL = Bundle.main.bundleURL
        let installParent = currentAppURL.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: installParent.path) else {
            throw UpdateError.installLocationNotWritable(installParent.path)
        }

        let helperDir = newAppURL.deletingLastPathComponent().deletingLastPathComponent()
        let backupURL = helperDir.appendingPathComponent("SnapAI-old-\(UUID().uuidString).app", isDirectory: true)
        let logURL = helperDir.appendingPathComponent("install.log")
        let scriptURL = helperDir.appendingPathComponent("install.sh")
        let script = """
        #!/bin/sh
        set -u
        APP_PATH="$1"
        NEW_APP="$2"
        BACKUP_PATH="$3"
        LOG_PATH="$4"

        while /usr/bin/pgrep -x "SnapAI" >/dev/null 2>&1; do
            /bin/sleep 0.2
        done

        /bin/rm -rf "$BACKUP_PATH" >>"$LOG_PATH" 2>&1
        if ! /bin/mv "$APP_PATH" "$BACKUP_PATH" >>"$LOG_PATH" 2>&1; then
            /usr/bin/open "$APP_PATH" >/dev/null 2>&1
            exit 1
        fi

        if ! /usr/bin/ditto "$NEW_APP" "$APP_PATH" >>"$LOG_PATH" 2>&1; then
            /bin/rm -rf "$APP_PATH" >>"$LOG_PATH" 2>&1
            /bin/mv "$BACKUP_PATH" "$APP_PATH" >>"$LOG_PATH" 2>&1
            /usr/bin/open "$APP_PATH" >/dev/null 2>&1
            exit 1
        fi

        /usr/bin/xattr -dr com.apple.quarantine "$APP_PATH" >/dev/null 2>&1
        /bin/rm -rf "$BACKUP_PATH" >>"$LOG_PATH" 2>&1
        /usr/bin/open "$APP_PATH" >/dev/null 2>&1
        exit 0
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = [scriptURL.path, currentAppURL.path, newAppURL.path, backupURL.path, logURL.path]
        try proc.run()

        let alert = NSAlert()
        alert.messageText = "正在安装 \(releaseTag)"
        alert.informativeText = "SnapAI 将退出,完成原位置替换后自动重新打开。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好")
        _ = run(alert)
        NSApp.terminate(nil)
    }

    private static func presentInstallError(_ error: Error, release: Release) {
        let alert = NSAlert(error: error)
        alert.messageText = "自动安装更新失败"
        alert.informativeText = "\(error.localizedDescription)\n\n你仍可打开 GitHub Release 页面手动下载。"
        alert.addButton(withTitle: "打开下载页")
        alert.addButton(withTitle: "取消")
        if run(alert) == .alertFirstButtonReturn {
            NSWorkspace.shared.open(release.htmlURL)
        }
    }

    private static func presentError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = "检查更新失败"
        alert.informativeText = error.localizedDescription
        run(alert)
    }

    @discardableResult
    private static func run(_ alert: NSAlert) -> NSApplication.ModalResponse {
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal()
    }

    private static func runTool(_ executable: String, arguments: [String]) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = arguments
        let err = Pipe()
        proc.standardError = err
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            let data = err.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "\(executable) failed"
            throw NSError(
                domain: "SnapAI.UpdateChecker",
                code: Int(proc.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
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
