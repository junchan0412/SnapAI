import AppKit
import Foundation
import SnapAILogic

enum UpdateCheckerApp {
    private typealias Release = UpdateChecker.Release
    private typealias Asset = UpdateChecker.Asset
    private typealias ReleaseManifest = UpdateChecker.ReleaseManifest
    private typealias UpdateError = UpdateChecker.UpdateError

    private static let repositoryURL = URL(string: "https://github.com/junchan0412/SnapAI")!
    private static let latestReleaseAPIURL = URL(string: "https://api.github.com/repos/junchan0412/SnapAI/releases/latest")!
    private static let latestReleasePageURL = URL(string: "https://github.com/junchan0412/SnapAI/releases/latest")!

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
        guard let tagName = UpdateChecker.releaseTag(from: http.url) else {
            throw NSError(
                domain: "SnapAI.UpdateChecker",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "GitHub Releases 网页未返回最新版本标签。"]
            )
        }

        return UpdateChecker.webFallbackRelease(tagName: tagName)
    }

    private static func presentResult(_ release: Release) {
        let current = currentVersion
        let latest = UpdateChecker.normalizedVersion(release.tagName)
        let currentDisplay = UpdateChecker.displayVersion(current)
        let latestDisplay = UpdateChecker.displayVersion(release.tagName)
        let hasUpdate: Bool
        do {
            hasUpdate = try UpdateChecker.compareOfficialVersions(latest, current) == .orderedDescending
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
        try UpdateChecker.requiredAppZipAsset(for: release)
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
        let actual = try UpdateChecker.sha256Hex(for: zipURL)
        let manifestAsset = try UpdateChecker.requiredManifestAsset(for: release, assetName: asset.name)
        let signatureAsset = try UpdateChecker.requiredManifestSignatureAsset(for: release,
                                                               assetName: manifestAsset.name)
        let manifestPayload = try await downloadManifest(manifestAsset)
        let signature = try await downloadManifestSignature(signatureAsset)
        try UpdateChecker.verifyManifestSignature(manifestData: manifestPayload.data,
                                    signatureData: signature)
        if let githubDigest = try UpdateChecker.validatedGitHubDigestSHA256(asset.digest) {
            let manifestDigest = try UpdateChecker.validatedManifestSHA256(from: manifestPayload.manifest,
                                                             releaseTag: release.tagName,
                                                             assetName: asset.name)
            guard githubDigest == manifestDigest else {
                throw UpdateError.invalidReleaseMetadata("GitHub digest 与已签名 manifest 中的 sha256 不一致。")
            }
        }
        let expectedBundleID = Bundle.main.bundleIdentifier ?? "com.snapai.app"
        let currentRequirement = try designatedRequirement(for: Bundle.main.bundleURL)
        try UpdateChecker.validatedManifestSigning(from: manifestPayload.manifest,
                                     expectedBundleID: expectedBundleID,
                                     expectedDesignatedRequirement: currentRequirement)
        let expected = try UpdateChecker.validatedManifestSHA256(from: manifestPayload.manifest,
                                                   releaseTag: release.tagName,
                                                   assetName: asset.name)
        guard actual == expected else {
            throw UpdateError.checksumMismatch(expected: expected, actual: actual)
        }
    }

    private static func downloadManifest(_ asset: Asset) async throws -> (data: Data, manifest: ReleaseManifest) {
        var request = updateRequest(url: asset.browserDownloadURL, accept: "application/json")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw UpdateError.invalidManifest("manifest 下载失败(status \(http.statusCode))。")
        }
        do {
            return (data, try JSONDecoder().decode(ReleaseManifest.self, from: data))
        } catch {
            throw UpdateError.invalidManifest(error.localizedDescription)
        }
    }

    private static func downloadManifestSignature(_ asset: Asset) async throws -> Data {
        var request = updateRequest(url: asset.browserDownloadURL, accept: "application/octet-stream")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw UpdateError.invalidManifestSignature("manifest 签名下载失败(status \(http.statusCode))。")
        }
        guard !data.isEmpty else {
            throw UpdateError.invalidManifestSignature("manifest 签名为空。")
        }
        return data
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
        try UpdateChecker.runTool("/usr/bin/ditto", arguments: ["-x", "-k", zipURL.path, unpackDir.path])

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
            try UpdateChecker.runTool("/usr/bin/codesign", arguments: ["--verify", "--deep", "--strict", url.path])
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
        let output = try UpdateChecker.runToolOutput("/usr/bin/codesign", arguments: ["-d", "-r-", appURL.path])
        guard let requirement = UpdateChecker.designatedRequirementLine(from: output) else {
            throw UpdateError.signingRequirementUnavailable(appURL.path)
        }
        return requirement
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
        UpdateChecker.recordLatestInstallLogURL(logURL)

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
        if UpdateChecker.latestInstallLogURL() != nil {
            alert.addButton(withTitle: "打开安装日志")
        }
        alert.addButton(withTitle: "取消")
        let response = run(alert)
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(release.htmlURL)
        } else if response == .alertSecondButtonReturn, let logURL = UpdateChecker.latestInstallLogURL() {
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
    private static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    private static var userAgent: String {
        "SnapAI/\(currentVersion) (+https://github.com/junchan0412/SnapAI)"
    }

    private struct GitHubAPIError: Decodable {
        let message: String
    }
}
