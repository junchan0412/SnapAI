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

    @MainActor
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

        guard hasUpdate else {
            presentUpToDate(currentDisplay: currentDisplay, latestDisplay: latestDisplay)
            return
        }

        let trimmedNotes = release.body?.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = (trimmedNotes?.isEmpty == false) ? trimmedNotes : nil
        let trimmedName = release.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = (trimmedName?.isEmpty == false) ? trimmedName! : "SnapAI \(latestDisplay)"

        let model = UpdateFlowModel(
            currentDisplay: currentDisplay,
            latestDisplay: latestDisplay,
            releaseTitle: title,
            releaseNotes: notes ?? "本次更新暂无详细说明,点「安装更新」即可获取最新版本。",
            hasNotes: notes != nil,
            autoInstall: autoInstallPreference
        )
        model.onInstall = { [weak model] in
            guard let model else { return }
            install(release, model: model)
        }
        model.onSkip = {
            setSkippedVersion(latest)
            UpdateWindowController.shared.close()
        }
        model.onRemindLater = { UpdateWindowController.shared.close() }
        model.onCancel = { UpdateWindowController.shared.cancelInstall() }
        model.onAutoInstallChanged = { setAutoInstallPreference($0) }
        UpdateWindowController.shared.present(model: model)
    }

    @MainActor
    private static func presentUpToDate(currentDisplay: String, latestDisplay: String) {
        let alert = NSAlert()
        alert.messageText = "SnapAI 已是最新版本"
        alert.informativeText = "当前版本: \(currentDisplay)\n最新版本: \(latestDisplay)"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好")
        _ = run(alert)
    }

    @MainActor
    private static func install(_ release: Release, model: UpdateFlowModel) {
        UpdateWindowController.shared.enterDownloading()
        let task = Task { await runInstall(release, model: model) }
        UpdateWindowController.shared.setInstallTask(task)
    }

    private static func installAsset(from release: Release) throws -> Asset {
        try UpdateChecker.requiredAppZipAsset(for: release)
    }

    private static func downloadWithProgress(_ asset: Asset, model: UpdateFlowModel) async throws -> URL {
        var request = updateRequest(url: asset.browserDownloadURL, accept: "application/octet-stream")
        request.timeoutInterval = 90

        let updateDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SnapAIUpdate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: updateDir, withIntermediateDirectories: true)
        let zipURL = updateDir.appendingPathComponent(asset.name)

        let downloader = UpdateProgressDownloader(destination: zipURL) { received, total in
            Task { @MainActor in
                model.receivedBytes = received
                model.totalBytes = total
            }
        }
        try await downloader.run(request: request)
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
        return true
    }

    /// 后台执行下载、校验、解包与安装;进度回调驱动进度窗,失败回退到错误提示。
    private static func runInstall(_ release: Release, model: UpdateFlowModel) async {
        do {
            let asset = try installAsset(from: release)
            let zipURL = try await downloadWithProgress(asset, model: model)
            await MainActor.run { model.phase = .installing }
            try await verifyDownload(zipURL: zipURL, asset: asset, release: release)
            let newAppURL = try unpackApp(from: zipURL)
            try await MainActor.run {
                try launchInstaller(newAppURL: newAppURL, releaseTag: release.tagName)
                scheduleTerminateAfterInstall()
            }
        } catch is CancellationError {
            await MainActor.run { UpdateWindowController.shared.close() }
        } catch {
            if (error as? URLError)?.code == .cancelled {
                await MainActor.run { UpdateWindowController.shared.close() }
            } else {
                await MainActor.run {
                    UpdateWindowController.shared.close()
                    presentInstallError(error, release: release)
                }
            }
        }
    }

    /// 安装器已启动,短暂展示「正在安装」后退出,让 helper 在原位置替换并自动重开。
    @MainActor
    private static func scheduleTerminateAfterInstall() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            NSApp.terminate(nil)
        }
    }

    // MARK: - 更新偏好持久化

    private static let autoInstallDefaultsKey = "SnapAI.Update.autoInstall"
    private static let skippedVersionDefaultsKey = "SnapAI.Update.skippedVersion"

    private static var autoInstallPreference: Bool {
        UserDefaults.standard.bool(forKey: autoInstallDefaultsKey)
    }

    private static func setAutoInstallPreference(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: autoInstallDefaultsKey)
    }

    private static func setSkippedVersion(_ version: String) {
        UserDefaults.standard.set(version, forKey: skippedVersionDefaultsKey)
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

/// 基于 URLSessionDownloadDelegate 的下载器,按字节回报进度并支持取消。
private final class UpdateProgressDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let onProgress: @Sendable (Int64, Int64) -> Void
    private var continuation: CheckedContinuation<Void, Error>?
    private var session: URLSession?

    init(destination: URL, onProgress: @escaping @Sendable (Int64, Int64) -> Void) {
        self.destination = destination
        self.onProgress = onProgress
        super.init()
    }

    func run(request: URLRequest) async throws {
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        self.session = session
        let task = session.downloadTask(with: request)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                self.continuation = continuation
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        onProgress(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        let continuation = self.continuation
        self.continuation = nil
        do {
            if let http = downloadTask.response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                throw UpdateChecker.UpdateError.downloadFailed(http.statusCode)
            }
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            continuation?.resume()
        } catch {
            continuation?.resume(throwing: error)
        }
        session.finishTasksAndInvalidate()
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        // 成功路径已在 didFinishDownloadingTo 处理;此处只处理失败/取消。
        guard let error else { return }
        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume(throwing: error)
        session.finishTasksAndInvalidate()
    }
}
