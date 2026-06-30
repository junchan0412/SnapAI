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
            uniqueAsset(named: expectedAppZipAssetName)
        }

        var manifestAsset: Asset? {
            uniqueAsset(named: expectedManifestAssetName)
        }

        var expectedAppZipAssetName: String {
            "SnapAI-\(versionedTag).zip"
        }

        var expectedManifestAssetName: String {
            "snapai-manifest-\(versionedTag).json"
        }

        private var versionedTag: String {
            UpdateChecker.versionedReleaseTag(tagName)
        }

        func assets(named name: String) -> [Asset] {
            assets.filter { $0.name == name }
        }

        private func uniqueAsset(named name: String) -> Asset? {
            let matches = assets(named: name)
            return matches.count == 1 ? matches[0] : nil
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

    enum InstallLogStatus: Equatable {
        case noRecord
        case untrustedLocation(String)
        case missing(String)
        case available(URL)

        var diagnosticCode: String {
            switch self {
            case .noRecord:
                return "no-record"
            case .untrustedLocation:
                return "untrusted-location"
            case .missing:
                return "missing"
            case .available:
                return "available"
            }
        }

        var diagnosticPath: String {
            switch self {
            case .noRecord:
                return "none"
            case .untrustedLocation(let path), .missing(let path):
                return path
            case .available(let url):
                return url.path
            }
        }

        var recoverySuggestion: String {
            switch self {
            case .noRecord:
                return "暂无自动更新日志;如更新失败,请重新检查更新后再复制诊断"
            case .untrustedLocation:
                return "已忽略不受信任的日志路径;请重新检查更新以生成新的 SnapAI 安装日志"
            case .missing:
                return "临时安装日志已不存在;请重新检查更新复现问题并复制新的安装日志"
            case .available:
                return "可通过命令面板或权限健康中心显示安装日志"
            }
        }

        var url: URL? {
            switch self {
            case .available(let url):
                return url
            case .noRecord, .untrustedLocation, .missing:
                return nil
            }
        }
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
        case invalidReleaseMetadata(String)
        case signingIdentityChanged(current: String, incoming: String)
        case signingRequirementUnavailable(String)

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

                API 检查失败: \(SensitiveTextSanitizer.sanitizedMessage(primary.localizedDescription))
                备用网页检查失败: \(SensitiveTextSanitizer.sanitizedMessage(fallback.localizedDescription))
                """
            case .checksumMismatch(let expected, let actual):
                return "更新包 SHA256 校验失败。\n期望: \(expected)\n实际: \(actual)"
            case .invalidManifest(let message):
                return "Release manifest 无法验证:\n\(SensitiveTextSanitizer.sanitizedMessage(message))"
            case .invalidReleaseMetadata(let message):
                return "Release 元数据无法验证:\n\(SensitiveTextSanitizer.sanitizedMessage(message))"
            case .signingIdentityChanged(let current, let incoming):
                return """
                更新包的签名身份与当前 SnapAI 不一致,已取消自动安装。

                这通常会导致钥匙串、辅助功能等系统授权在更新后重新询问。请确认发布包继续使用同一个稳定签名证书。

                当前: \(current)
                新包: \(incoming)
                """
            case .signingRequirementUnavailable(let path):
                return "无法读取应用签名要求,已取消自动安装:\n\(path)"
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

        return webFallbackRelease(tagName: tagName)
    }

    private static func presentResult(_ release: Release) {
        let current = currentVersion
        let latest = normalizedVersion(release.tagName)
        let currentDisplay = displayVersion(current)
        let latestDisplay = displayVersion(release.tagName)
        let hasUpdate: Bool
        do {
            hasUpdate = try compareOfficialVersions(latest, current) == .orderedDescending
        } catch {
            presentError(error)
            return
        }

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
        try requiredAppZipAsset(for: release)
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
        if let expected = try validatedGitHubDigestSHA256(asset.digest) {
            guard actual == expected else {
                throw UpdateError.checksumMismatch(expected: expected, actual: actual)
            }
            return
        }

        let manifestAsset = try requiredManifestAsset(for: release, assetName: asset.name)
        let manifest = try await downloadManifest(manifestAsset)
        let expected = try validatedManifestSHA256(from: manifest,
                                                   releaseTag: release.tagName,
                                                   assetName: asset.name)
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

    static func webFallbackRelease(tagName: String) -> Release {
        let htmlURL = releaseTagURL(tagName)
        let versionedTag = versionedReleaseTag(tagName)
        let appAssetName = "SnapAI-\(versionedTag).zip"
        let manifestAssetName = "snapai-manifest-\(versionedTag).json"
        return Release(
            tagName: tagName,
            name: nil,
            htmlURL: htmlURL,
            assets: [
                Asset(
                    name: appAssetName,
                    browserDownloadURL: releaseDownloadURL(tagName: tagName, assetName: appAssetName),
                    digest: nil
                ),
                Asset(
                    name: manifestAssetName,
                    browserDownloadURL: releaseDownloadURL(tagName: tagName, assetName: manifestAssetName),
                    digest: nil
                )
            ]
        )
    }

    static func requiredManifestAsset(for release: Release, assetName: String) throws -> Asset {
        let matches = release.assets(named: release.expectedManifestAssetName)
        guard matches.count == 1, let manifestAsset = matches.first else {
            if matches.isEmpty {
                throw UpdateError.invalidReleaseMetadata(
                    "\(assetName) 缺少 GitHub digest,且 Release 中没有 \(release.expectedManifestAssetName)。"
                )
            }
            throw UpdateError.invalidReleaseMetadata(
                "Release 中存在重复资产 \(release.expectedManifestAssetName),已取消自动安装。"
            )
        }
        return manifestAsset
    }

    static func requiredAppZipAsset(for release: Release) throws -> Asset {
        let matches = release.assets(named: release.expectedAppZipAssetName)
        guard matches.count == 1, let asset = matches.first else {
            if matches.isEmpty {
                throw UpdateError.noInstallAsset
            }
            throw UpdateError.invalidReleaseMetadata(
                "Release 中存在重复资产 \(release.expectedAppZipAssetName),已取消自动安装。"
            )
        }
        return asset
    }

    static func validatedGitHubDigestSHA256(_ digest: String?) throws -> String? {
        guard let digest else { return nil }
        let trimmed = digest.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        guard !lower.isEmpty else {
            throw UpdateError.invalidReleaseMetadata("GitHub asset digest 为空。")
        }
        guard let separator = lower.firstIndex(of: ":") else {
            throw UpdateError.invalidReleaseMetadata("GitHub asset digest 格式无效。")
        }
        let algorithm = String(lower[..<separator])
        let value = String(lower[lower.index(after: separator)...])
        guard algorithm == "sha256" else {
            throw UpdateError.invalidReleaseMetadata("GitHub asset digest 算法不受支持: \(algorithm)。")
        }
        guard let sha256 = normalizedSHA256(value) else {
            throw UpdateError.invalidReleaseMetadata("GitHub asset digest 的 sha256 格式无效。")
        }
        return sha256
    }

    static func validatedManifestSHA256(from manifest: ReleaseManifest,
                                        releaseTag: String,
                                        assetName: String) throws -> String {
        guard let manifestVersion = manifest.version?.trimmingCharacters(in: .whitespacesAndNewlines),
              !manifestVersion.isEmpty else {
            throw UpdateError.invalidManifest("manifest 缺少版本号。")
        }
        let expectedVersion = normalizedVersion(releaseTag)
        guard normalizedVersion(manifestVersion) == expectedVersion else {
            throw UpdateError.invalidManifest("manifest 版本 \(manifestVersion) 与 Release \(releaseTag) 不一致。")
        }

        let matches = manifest.assets.filter { $0.name == assetName }
        guard matches.count == 1, let match = matches.first else {
            if matches.isEmpty {
                throw UpdateError.invalidManifest("manifest 中未找到 \(assetName) 的 sha256。")
            }
            throw UpdateError.invalidManifest("manifest 中存在重复资产 \(assetName)。")
        }
        guard let sha256 = normalizedSHA256(match.sha256) else {
            throw UpdateError.invalidManifest("manifest 中 \(assetName) 的 sha256 格式无效。")
        }
        return sha256
    }

    static func normalizedSHA256(_ value: String) -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hexCharacters = CharacterSet(charactersIn: "0123456789abcdef")
        guard normalized.count == 64,
              normalized.unicodeScalars.allSatisfy({ hexCharacters.contains($0) }) else {
            return nil
        }
        return normalized
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

    static func versionedReleaseTag(_ tagName: String) -> String {
        "v\(normalizedVersion(tagName))"
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
            try validateSigningContinuity(newAppURL: url)
            return url
        }
        throw UpdateError.invalidArchive
    }

    private static func validateSigningContinuity(newAppURL: URL) throws {
        let currentRequirement = try designatedRequirement(for: Bundle.main.bundleURL)
        let incomingRequirement = try designatedRequirement(for: newAppURL)
        guard currentRequirement == incomingRequirement else {
            throw UpdateError.signingIdentityChanged(current: currentRequirement,
                                                     incoming: incomingRequirement)
        }
    }

    private static func designatedRequirement(for appURL: URL) throws -> String {
        let output = try runToolOutput("/usr/bin/codesign", arguments: ["-d", "-r-", appURL.path])
        guard let requirement = designatedRequirementLine(from: output) else {
            throw UpdateError.signingRequirementUnavailable(appURL.path)
        }
        return requirement
    }

    static func designatedRequirementLine(from codesignOutput: String) -> String? {
        codesignOutput
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.hasPrefix("designated =>") }
            .map { String($0.dropFirst("designated =>".count)).trimmingCharacters(in: .whitespacesAndNewlines) }
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
        alert.informativeText = "\(SensitiveTextSanitizer.sanitizedMessage(error.localizedDescription))\n\n你仍可打开 GitHub Release 页面手动下载。"
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
        alert.informativeText = SensitiveTextSanitizer.sanitizedMessage(error.localizedDescription)
        run(alert)
    }

    @discardableResult
    private static func run(_ alert: NSAlert) -> NSApplication.ModalResponse {
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal()
    }

    private static func runTool(_ executable: String, arguments: [String]) throws {
        _ = try runToolOutput(executable, arguments: arguments)
    }

    @discardableResult
    private static func runToolOutput(_ executable: String, arguments: [String]) throws -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = arguments
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        try proc.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        guard proc.terminationStatus == 0 else {
            let message = output.isEmpty ? "\(executable) failed" : output
            throw NSError(
                domain: "SnapAI.UpdateChecker",
                code: Int(proc.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
        return output
    }

    static func latestInstallLogURL() -> URL? {
        latestInstallLogStatus().url
    }

    static func latestInstallLogURL(storedPath: String?,
                                    fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
                                    trustedTemporaryDirectory: URL = FileManager.default.temporaryDirectory) -> URL? {
        latestInstallLogStatus(storedPath: storedPath,
                               fileExists: fileExists,
                               trustedTemporaryDirectory: trustedTemporaryDirectory).url
    }

    static func latestInstallLogStatus() -> InstallLogStatus {
        latestInstallLogStatus(storedPath: UserDefaults.standard.string(forKey: latestInstallLogKey))
    }

    static func latestInstallLogStatus(storedPath: String?,
                                       fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
                                       trustedTemporaryDirectory: URL = FileManager.default.temporaryDirectory) -> InstallLogStatus {
        guard let path = storedPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else {
            return .noRecord
        }
        guard isTrustedInstallLogPath(path,
                                      trustedTemporaryDirectory: trustedTemporaryDirectory) else {
            return .untrustedLocation(path)
        }
        guard fileExists(path) else {
            return .missing(path)
        }
        return .available(URL(fileURLWithPath: path))
    }

    private static func isTrustedInstallLogPath(_ path: String,
                                                trustedTemporaryDirectory: URL) -> Bool {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard url.lastPathComponent == "install.log" else { return false }
        let updateDirectory = url.deletingLastPathComponent()
        guard updateDirectory.lastPathComponent.hasPrefix("SnapAIUpdate-") else { return false }
        let trustedRoot = trustedTemporaryDirectory.standardizedFileURL
        return updateDirectory.deletingLastPathComponent().path == trustedRoot.path
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
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first,
              first == "v" || first == "V" else { return trimmed }
        return String(trimmed.dropFirst())
    }

    private static func displayVersion(_ version: String) -> String {
        "v\(normalizedVersion(version))"
    }

    static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = officialVersionComponents(lhs) ?? lhs.split(separator: ".").map { Int($0) ?? 0 }
        let right = officialVersionComponents(rhs) ?? rhs.split(separator: ".").map { Int($0) ?? 0 }
        return compareVersionComponents(left, right)
    }

    static func compareOfficialVersions(_ lhs: String, _ rhs: String) throws -> ComparisonResult {
        guard let left = officialVersionComponents(lhs) else {
            throw UpdateError.invalidReleaseMetadata("版本号格式无效: \(lhs)。")
        }
        guard let right = officialVersionComponents(rhs) else {
            throw UpdateError.invalidReleaseMetadata("当前版本号格式无效: \(rhs)。")
        }
        return compareVersionComponents(left, right)
    }

    static func officialVersionComponents(_ version: String) -> [Int]? {
        let normalized = normalizedVersion(version)
        guard !normalized.isEmpty else { return nil }
        let parts = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }
        let digits = CharacterSet.decimalDigits
        var components: [Int] = []
        for part in parts {
            guard !part.isEmpty,
                  part.unicodeScalars.allSatisfy({ digits.contains($0) }),
                  let value = Int(part) else {
                return nil
            }
            components.append(value)
        }
        return components
    }

    private static func compareVersionComponents(_ left: [Int], _ right: [Int]) -> ComparisonResult {
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
