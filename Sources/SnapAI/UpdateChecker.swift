import AppKit
import CryptoKit
import Foundation

enum UpdateChecker {
    private static let repositoryURL = URL(string: "https://github.com/junchan0412/SnapAI")!
    private static let latestReleaseAPIURL = URL(string: "https://api.github.com/repos/junchan0412/SnapAI/releases/latest")!
    private static let latestReleasePageURL = URL(string: "https://github.com/junchan0412/SnapAI/releases/latest")!
    private static let latestInstallLogKey = "SnapAI.UpdateChecker.latestInstallLogPath"

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

        var manifestAsset: Asset? {
            assets.first { asset in
                let lower = asset.name.lowercased()
                return lower.hasSuffix(".json") && lower.contains("manifest")
            }
        }
    }

    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL
        let digest: String?

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
            case digest
        }
    }

    struct ReleaseManifest: Decodable {
        struct ManifestAsset: Decodable {
            let name: String
            let sha256: String
        }

        let version: String?
        let assets: [ManifestAsset]
    }

    enum UpdateError: LocalizedError {
        case noInstallAsset
        case downloadFailed(Int)
        case invalidArchive
        case bundleMismatch
        case installLocationNotWritable(String)
        case releaseLookupFailed(primary: Error, fallback: Error)
        case checksumMismatch(expected: String, actual: String)
        case invalidManifest(String)

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
            case .releaseLookupFailed(let primary, let fallback):
                return """
                GitHub Releases 暂不可用。

                API 检查失败: \(primary.localizedDescription)
                备用网页检查失败: \(fallback.localizedDescription)
                """
            case .checksumMismatch(let expected, let actual):
                return "更新包 SHA256 校验失败。\n期望: \(expected)\n实际: \(actual)"
            case .invalidManifest(let message):
                return "Release manifest 无法验证:\n\(message)"
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
        do {
            return try await latestReleaseFromAPI()
        } catch {
            let apiError = error
            do {
                return try await latestReleaseFromWebFallback()
            } catch {
                throw UpdateError.releaseLookupFailed(primary: apiError, fallback: error)
            }
        }
    }

    private static func latestReleaseFromAPI() async throws -> Release {
        var request = updateRequest(url: latestReleaseAPIURL, accept: "application/vnd.github+json")
        request.timeoutInterval = 12

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw NSError(
                domain: "SnapAI.UpdateChecker",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: apiErrorMessage(statusCode: http.statusCode, data: data)]
            )
        }
        return try JSONDecoder().decode(Release.self, from: data)
    }

    private static func latestReleaseFromWebFallback() async throws -> Release {
        var request = updateRequest(url: uncachedLatestReleasePageURL(), accept: "text/html,application/xhtml+xml")
        request.timeoutInterval = 12

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw NSError(
                domain: "SnapAI.UpdateChecker",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "GitHub Releases 网页暂不可用(status \(http.statusCode))。"]
            )
        }
        guard let tagName = releaseTag(from: http.url) else {
            throw NSError(
                domain: "SnapAI.UpdateChecker",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "GitHub Releases 网页未返回最新版本标签。"]
            )
        }

        let htmlURL = releaseTagURL(tagName)
        let assetName = "SnapAI-\(tagName).zip"
        return Release(
            tagName: tagName,
            name: nil,
            htmlURL: htmlURL,
            assets: [
                Asset(
                    name: assetName,
                    browserDownloadURL: releaseDownloadURL(tagName: tagName, assetName: assetName),
                    digest: nil
                )
            ]
        )
    }

    private static func presentResult(_ release: Release) {
        let current = currentVersion
        let latest = normalizedVersion(release.tagName)
        let currentDisplay = displayVersion(current)
        let latestDisplay = displayVersion(release.tagName)
        let hasUpdate = compareVersions(latest, current) == .orderedDescending

        let alert = NSAlert()
        alert.messageText = hasUpdate ? "发现新版本 \(latestDisplay)" : "SnapAI 已是最新版本"
        alert.informativeText = hasUpdate
            ? "当前版本: \(currentDisplay)\n最新版本: \(latestDisplay)\n\n建议直接安装更新并重启 SnapAI,避免手动下载后覆盖安装。若发布包持续使用同一个稳定签名身份,辅助功能权限通常可保留。"
            : "当前版本: \(currentDisplay)\n最新版本: \(latestDisplay)"
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
                try await verifyDownload(zipURL: zipURL, asset: asset, release: release)
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
        var request = updateRequest(url: asset.browserDownloadURL, accept: "application/octet-stream")
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

    private static func verifyDownload(zipURL: URL, asset: Asset, release: Release) async throws {
        let actual = try sha256Hex(for: zipURL)
        if let expected = sha256FromGitHubDigest(asset.digest) {
            guard actual == expected else {
                throw UpdateError.checksumMismatch(expected: expected, actual: actual)
            }
            return
        }

        guard let manifestAsset = release.manifestAsset else { return }
        let manifest = try await downloadManifest(manifestAsset)
        guard let expected = manifest.assets.first(where: { $0.name == asset.name })?.sha256.lowercased() else {
            throw UpdateError.invalidManifest("manifest 中未找到 \(asset.name) 的 sha256。")
        }
        guard actual == expected else {
            throw UpdateError.checksumMismatch(expected: expected, actual: actual)
        }
    }

    private static func downloadManifest(_ asset: Asset) async throws -> ReleaseManifest {
        var request = updateRequest(url: asset.browserDownloadURL, accept: "application/json")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw UpdateError.invalidManifest("manifest 下载失败(status \(http.statusCode))。")
        }
        do {
            return try JSONDecoder().decode(ReleaseManifest.self, from: data)
        } catch {
            throw UpdateError.invalidManifest(error.localizedDescription)
        }
    }

    private static func sha256FromGitHubDigest(_ digest: String?) -> String? {
        guard let digest else { return nil }
        let lower = digest.lowercased()
        if lower.hasPrefix("sha256:") {
            return String(lower.dropFirst("sha256:".count))
        }
        return nil
    }

    static func sha256Hex(for url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func updateRequest(url: URL, accept: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        return request
    }

    private static func apiErrorMessage(statusCode: Int, data: Data) -> String {
        var message = "GitHub API 暂不可用(status \(statusCode))。"
        if let error = try? JSONDecoder().decode(GitHubAPIError.self, from: data),
           !error.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            message += "\n\(error.message)"
        }
        return message
    }

    static func releaseTag(from url: URL?) -> String? {
        guard let components = url?.pathComponents,
              let tagIndex = components.firstIndex(of: "tag"),
              components.indices.contains(tagIndex + 1) else {
            return nil
        }
        return components[tagIndex + 1]
    }

    private static func releaseTagURL(_ tagName: String) -> URL {
        repositoryURL
            .appendingPathComponent("releases")
            .appendingPathComponent("tag")
            .appendingPathComponent(tagName)
    }

    private static func releaseDownloadURL(tagName: String, assetName: String) -> URL {
        repositoryURL
            .appendingPathComponent("releases")
            .appendingPathComponent("download")
            .appendingPathComponent(tagName)
            .appendingPathComponent(assetName)
    }

    private static func uncachedLatestReleasePageURL() -> URL {
        var components = URLComponents(url: latestReleasePageURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "snapai_cache_bust", value: String(Int(Date().timeIntervalSince1970)))
        ]
        return components?.url ?? latestReleasePageURL
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
        UserDefaults.standard.set(logURL.path, forKey: latestInstallLogKey)

        if try launchBundledUpdaterIfAvailable(currentAppURL: currentAppURL,
                                               newAppURL: newAppURL,
                                               backupURL: backupURL,
                                               logURL: logURL,
                                               releaseTag: releaseTag) {
            return
        }

        let scriptURL = helperDir.appendingPathComponent("install.sh")
        let script = """
        #!/bin/sh
        set -u
        APP_PATH="$1"
        NEW_APP="$2"
        BACKUP_PATH="$3"
        LOG_PATH="$4"
        OLD_PID="$5"

        log() {
            /bin/echo "$(/bin/date '+%Y-%m-%d %H:%M:%S') $*" >>"$LOG_PATH"
        }

        relaunch_app() {
            attempt=1
            while [ "$attempt" -le 5 ]; do
                log "relaunch attempt $attempt: $APP_PATH"
                if /usr/bin/open -n -F "$APP_PATH" >>"$LOG_PATH" 2>&1; then
                    /bin/sleep 1
                    if /usr/bin/pgrep -x "SnapAI" >/dev/null 2>&1; then
                        log "relaunch succeeded"
                        return 0
                    fi
                fi
                attempt=$((attempt + 1))
                /bin/sleep 1
            done

            log "relaunch failed after retries"
            return 1
        }

        log "installer started"
        waited=0
        while /bin/kill -0 "$OLD_PID" >/dev/null 2>&1; do
            /bin/sleep 0.2
            waited=$((waited + 1))
            if [ "$waited" -ge 300 ]; then
                log "old process $OLD_PID did not exit within 60s"
                exit 1
            fi
        done
        /bin/sleep 0.4
        log "old process exited"

        log "moving current app to backup"
        /bin/rm -rf "$BACKUP_PATH" >>"$LOG_PATH" 2>&1
        if ! /bin/mv "$APP_PATH" "$BACKUP_PATH" >>"$LOG_PATH" 2>&1; then
            log "failed to move current app to backup"
            relaunch_app
            exit 1
        fi

        log "copying new app into place"
        if ! /usr/bin/ditto "$NEW_APP" "$APP_PATH" >>"$LOG_PATH" 2>&1; then
            log "failed to copy new app; restoring backup"
            /bin/rm -rf "$APP_PATH" >>"$LOG_PATH" 2>&1
            /bin/mv "$BACKUP_PATH" "$APP_PATH" >>"$LOG_PATH" 2>&1
            relaunch_app
            exit 1
        fi

        log "clearing extended attributes"
        /usr/bin/xattr -cr "$APP_PATH" >>"$LOG_PATH" 2>&1
        /bin/rm -rf "$BACKUP_PATH" >>"$LOG_PATH" 2>&1
        log "installation complete"
        relaunch_app
        exit 0
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
        proc.arguments = [
            scriptURL.path,
            currentAppURL.path,
            newAppURL.path,
            backupURL.path,
            logURL.path,
            String(ProcessInfo.processInfo.processIdentifier)
        ]
        if let null = FileHandle(forWritingAtPath: "/dev/null") {
            proc.standardOutput = null
            proc.standardError = null
        }
        try proc.run()
        presentInstallStarted(releaseTag)
    }

    @MainActor
    private static func launchBundledUpdaterIfAvailable(currentAppURL: URL,
                                                        newAppURL: URL,
                                                        backupURL: URL,
                                                        logURL: URL,
                                                        releaseTag: String) throws -> Bool {
        let helperURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Helpers")
            .appendingPathComponent("SnapAIUpdater")
        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            return false
        }

        let proc = Process()
        proc.executableURL = helperURL
        proc.arguments = [
            currentAppURL.path,
            newAppURL.path,
            backupURL.path,
            logURL.path,
            String(ProcessInfo.processInfo.processIdentifier)
        ]
        if let null = FileHandle(forWritingAtPath: "/dev/null") {
            proc.standardOutput = null
            proc.standardError = null
        }
        try proc.run()
        presentInstallStarted(releaseTag)
        return true
    }

    @MainActor
    private static func presentInstallStarted(_ releaseTag: String) {
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
        if latestInstallLogURL() != nil {
            alert.addButton(withTitle: "打开安装日志")
        }
        alert.addButton(withTitle: "取消")
        let response = run(alert)
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(release.htmlURL)
        } else if response == .alertSecondButtonReturn, let logURL = latestInstallLogURL() {
            NSWorkspace.shared.open(logURL)
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
        let data = err.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            let message = String(data: data, encoding: .utf8) ?? "\(executable) failed"
            throw NSError(
                domain: "SnapAI.UpdateChecker",
                code: Int(proc.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
    }

    static func latestInstallLogURL() -> URL? {
        guard let path = UserDefaults.standard.string(forKey: latestInstallLogKey),
              FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    private static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    private static var userAgent: String {
        "SnapAI/\(currentVersion) (+https://github.com/junchan0412/SnapAI)"
    }

    private struct GitHubAPIError: Decodable {
        let message: String
    }

    static func normalizedVersion(_ version: String) -> String {
        version.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
    }

    private static func displayVersion(_ version: String) -> String {
        "v\(normalizedVersion(version))"
    }

    static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
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
