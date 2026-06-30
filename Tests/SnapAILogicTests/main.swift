import Foundation
import ApplicationServices
import Carbon.HIToolbox

var failures: [String] = []

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        failures.append(message)
    }
}

func testVersionNormalizationAndCompare() {
    expect(UpdateChecker.normalizedVersion("v1.2.3") == "1.2.3", "normalizes v prefix")
    expect(UpdateChecker.normalizedVersion(" V1.2.3 ") == "1.2.3", "normalizes uppercase v prefix and trims whitespace")
    expect(UpdateChecker.normalizedVersion("1.2.3v") == "1.2.3v", "does not trim trailing v characters")
    expect(UpdateChecker.officialVersionComponents("v1.2.3") == [1, 2, 3], "parses official numeric release versions")
    expect(UpdateChecker.officialVersionComponents("1.2.0-beta") == nil, "rejects prerelease suffixes for official updates")
    expect(UpdateChecker.officialVersionComponents("1..2") == nil, "rejects empty version components")
    expect(UpdateChecker.compareVersions("1.2.0", "1.1.9") == .orderedDescending, "orders newer version")
    expect(UpdateChecker.compareVersions("1.2", "1.2.0") == .orderedSame, "pads missing version parts")
    expect(UpdateChecker.compareVersions("1.2.0", "1.2.1") == .orderedAscending, "orders older version")
    expect((try? UpdateChecker.compareOfficialVersions("v1.2.0", "1.2")) == .orderedSame,
           "official version comparison pads missing parts")
    expect((try? UpdateChecker.compareOfficialVersions("1.2.1", "1.2.0")) == .orderedDescending,
           "official version comparison orders newer stable releases")

    func officialCompareError(_ lhs: String, _ rhs: String) -> String {
        do {
            _ = try UpdateChecker.compareOfficialVersions(lhs, rhs)
            return ""
        } catch {
            return error.localizedDescription
        }
    }
    expect(officialCompareError("1.2.0-beta", "1.2.0").contains("版本号格式无效"),
           "official version comparison rejects prerelease latest versions")
    expect(officialCompareError("1.2.0", "dev").contains("当前版本号格式无效"),
           "official version comparison rejects invalid current versions")
}

func testReleaseTagParsing() {
    let url = URL(string: "https://github.com/junchan0412/SnapAI/releases/tag/v1.2.3")
    expect(UpdateChecker.releaseTag(from: url) == "v1.2.3", "parses release tag URL")
    expect(UpdateChecker.releaseTag(from: URL(string: "https://github.com/junchan0412/SnapAI/releases/latest")) == nil,
           "ignores latest URL without tag component")
}

func testReleaseAssetSelectionUsesExactVersionedNames() {
    func asset(_ name: String) -> UpdateChecker.Asset {
        UpdateChecker.Asset(name: name,
                            browserDownloadURL: URL(string: "https://example.test/\(name)")!,
                            digest: nil)
    }

    let release = UpdateChecker.Release(
        tagName: "v1.2.0",
        name: nil,
        htmlURL: URL(string: "https://github.com/junchan0412/SnapAI/releases/tag/v1.2.0")!,
        assets: [
            asset("SnapAI-v1.2.0-symbols.zip"),
            asset("SnapAI-v1.1.9.zip"),
            asset("SnapAI-debug-v1.2.0.zip"),
            asset("snapai-manifest-v1.1.9.json"),
            asset("snapai-manifest-latest.json"),
            asset("SnapAI-v1.2.0.zip"),
            asset("snapai-manifest-v1.2.0.json")
        ]
    )

    expect(release.appZipAsset?.name == "SnapAI-v1.2.0.zip",
           "release asset selection chooses the exact app zip for the release tag")
    expect(release.manifestAsset?.name == "snapai-manifest-v1.2.0.json",
           "release asset selection chooses the exact manifest for the release tag")
    expect(release.expectedAppZipAssetName == "SnapAI-v1.2.0.zip",
           "release asset selection exposes the expected app zip name")
    expect(release.expectedManifestAssetName == "snapai-manifest-v1.2.0.json",
           "release asset selection exposes the expected manifest name")

    let missingExactRelease = UpdateChecker.Release(
        tagName: "v1.2.0",
        name: nil,
        htmlURL: URL(string: "https://github.com/junchan0412/SnapAI/releases/tag/v1.2.0")!,
        assets: [
            asset("SnapAI-v1.2.0-symbols.zip"),
            asset("SnapAI-v1.1.9.zip"),
            asset("snapai-manifest-latest.json")
        ]
    )
    expect(missingExactRelease.appZipAsset == nil,
           "release asset selection does not fall back to fuzzy zip matches")
    expect(missingExactRelease.manifestAsset == nil,
           "release asset selection does not fall back to fuzzy manifest matches")

    let bareTagRelease = UpdateChecker.Release(
        tagName: "1.2.0",
        name: nil,
        htmlURL: URL(string: "https://github.com/junchan0412/SnapAI/releases/tag/1.2.0")!,
        assets: [
            asset("SnapAI-v1.2.0.zip"),
            asset("snapai-manifest-v1.2.0.json")
        ]
    )
    expect(bareTagRelease.appZipAsset?.name == "SnapAI-v1.2.0.zip",
           "release asset selection normalizes bare numeric release tags")
    expect(bareTagRelease.manifestAsset?.name == "snapai-manifest-v1.2.0.json",
           "release manifest selection normalizes bare numeric release tags")

    let fallbackRelease = UpdateChecker.webFallbackRelease(tagName: "1.2.0")
    expect(fallbackRelease.appZipAsset?.name == "SnapAI-v1.2.0.zip",
           "web fallback release includes the exact app zip asset")
    expect(fallbackRelease.manifestAsset?.name == "snapai-manifest-v1.2.0.json",
           "web fallback release includes the exact manifest asset")
    expect(fallbackRelease.assets.count == 2,
           "web fallback release constructs both install and checksum assets")

    let duplicateZipRelease = UpdateChecker.Release(
        tagName: "v1.2.0",
        name: nil,
        htmlURL: URL(string: "https://github.com/junchan0412/SnapAI/releases/tag/v1.2.0")!,
        assets: [
            asset("SnapAI-v1.2.0.zip"),
            asset("SnapAI-v1.2.0.zip"),
            asset("snapai-manifest-v1.2.0.json")
        ]
    )
    expect(duplicateZipRelease.appZipAsset == nil,
           "release asset selection does not pick between duplicate app zip assets")
    do {
        _ = try UpdateChecker.requiredAppZipAsset(for: duplicateZipRelease)
        expect(false, "duplicate app zip assets fail before install")
    } catch {
        expect(error.localizedDescription.contains("重复资产 SnapAI-v1.2.0.zip"),
               "duplicate app zip error names the ambiguous asset")
    }

    let duplicateManifestRelease = UpdateChecker.Release(
        tagName: "v1.2.0",
        name: nil,
        htmlURL: URL(string: "https://github.com/junchan0412/SnapAI/releases/tag/v1.2.0")!,
        assets: [
            asset("SnapAI-v1.2.0.zip"),
            asset("snapai-manifest-v1.2.0.json"),
            asset("snapai-manifest-v1.2.0.json")
        ]
    )
    expect(duplicateManifestRelease.manifestAsset == nil,
           "release asset selection does not pick between duplicate manifest assets")
    do {
        _ = try UpdateChecker.requiredManifestAsset(for: duplicateManifestRelease,
                                                    assetName: "SnapAI-v1.2.0.zip")
        expect(false, "duplicate manifest assets fail before checksum fallback")
    } catch {
        expect(error.localizedDescription.contains("重复资产 snapai-manifest-v1.2.0.json"),
               "duplicate manifest error names the ambiguous asset")
    }
}

func testGitHubAssetDigestValidation() {
    let upperSHA = String(repeating: "A", count: 64)
    let lowerSHA = String(repeating: "a", count: 64)

    let validated = try? UpdateChecker.validatedGitHubDigestSHA256(" sha256:\(upperSHA)\n")
    expect(validated == lowerSHA,
           "validates and normalizes GitHub sha256 asset digests")
    let missing = try? UpdateChecker.validatedGitHubDigestSHA256(nil)
    expect(missing == nil,
           "missing GitHub asset digests allow manifest fallback")

    func digestError(_ digest: String?) -> String {
        do {
            _ = try UpdateChecker.validatedGitHubDigestSHA256(digest)
            return ""
        } catch {
            return error.localizedDescription
        }
    }

    expect(digestError("").contains("digest 为空"),
           "rejects empty GitHub asset digests")
    expect(digestError("sha512:\(lowerSHA)").contains("算法不受支持"),
           "rejects unsupported GitHub asset digest algorithms")
    expect(digestError("sha256:1234").contains("sha256 格式无效"),
           "rejects malformed GitHub asset digest values")
    expect(digestError(lowerSHA).contains("格式无效"),
           "rejects GitHub asset digests without an algorithm prefix")
}

func testChecksumSourceRequiresDigestOrManifest() {
    func asset(_ name: String, digest: String? = nil) -> UpdateChecker.Asset {
        UpdateChecker.Asset(name: name,
                            browserDownloadURL: URL(string: "https://example.test/\(name)")!,
                            digest: digest)
    }
    let release = UpdateChecker.Release(
        tagName: "v1.2.0",
        name: nil,
        htmlURL: URL(string: "https://github.com/junchan0412/SnapAI/releases/tag/v1.2.0")!,
        assets: [
            asset("SnapAI-v1.2.0.zip"),
            asset("snapai-manifest-v1.2.0.json")
        ]
    )
    let manifestAsset = try? UpdateChecker.requiredManifestAsset(for: release,
                                                                 assetName: "SnapAI-v1.2.0.zip")
    expect(manifestAsset?.name == "snapai-manifest-v1.2.0.json",
           "digest-less release assets use the exact manifest as checksum source")

    let missingManifest = UpdateChecker.Release(
        tagName: "v1.2.0",
        name: nil,
        htmlURL: URL(string: "https://github.com/junchan0412/SnapAI/releases/tag/v1.2.0")!,
        assets: [
            asset("SnapAI-v1.2.0.zip")
        ]
    )
    do {
        _ = try UpdateChecker.requiredManifestAsset(for: missingManifest,
                                                    assetName: "SnapAI-v1.2.0.zip")
        expect(false, "digest-less release assets without manifest fail before install")
    } catch {
        let message = error.localizedDescription
        expect(message.contains("缺少 GitHub digest"),
               "missing checksum source error explains missing digest")
        expect(message.contains("snapai-manifest-v1.2.0.json"),
               "missing checksum source error names the expected manifest asset")
    }
}

func testReleaseManifestValidation() {
    let assetName = "SnapAI-v1.2.0.zip"
    let upperSHA = String(repeating: "A", count: 64)
    let lowerSHA = String(repeating: "a", count: 64)
    let validManifest = UpdateChecker.ReleaseManifest(
        version: " 1.2.0 ",
        assets: [
            UpdateChecker.ReleaseManifest.ManifestAsset(name: assetName, sha256: " \(upperSHA)\n")
        ]
    )

    let validated = try? UpdateChecker.validatedManifestSHA256(from: validManifest,
                                                               releaseTag: "v1.2.0",
                                                               assetName: assetName)
    expect(validated == lowerSHA, "validates manifest version and normalizes sha256")
    expect(UpdateChecker.normalizedSHA256(" \(upperSHA)\n") == lowerSHA,
           "normalizes uppercase sha256 values")
    expect(UpdateChecker.normalizedSHA256(String(repeating: "g", count: 64)) == nil,
           "rejects non-hex sha256 values")

    func manifestError(_ manifest: UpdateChecker.ReleaseManifest) -> String {
        do {
            _ = try UpdateChecker.validatedManifestSHA256(from: manifest,
                                                          releaseTag: "v1.2.0",
                                                          assetName: assetName)
            return ""
        } catch {
            return error.localizedDescription
        }
    }

    let missingVersion = UpdateChecker.ReleaseManifest(version: nil, assets: validManifest.assets)
    expect(manifestError(missingVersion).contains("缺少版本号"),
           "rejects manifests without a version")

    let mismatchedVersion = UpdateChecker.ReleaseManifest(version: "v1.3.0", assets: validManifest.assets)
    expect(manifestError(mismatchedVersion).contains("不一致"),
           "rejects manifests whose version differs from the release tag")

    let missingAsset = UpdateChecker.ReleaseManifest(version: "v1.2.0", assets: [
        UpdateChecker.ReleaseManifest.ManifestAsset(name: "Other.zip", sha256: lowerSHA)
    ])
    expect(manifestError(missingAsset).contains("未找到 \(assetName)"),
           "rejects manifests that do not list the downloaded asset")

    let duplicateAsset = UpdateChecker.ReleaseManifest(version: "v1.2.0", assets: [
        UpdateChecker.ReleaseManifest.ManifestAsset(name: assetName, sha256: lowerSHA),
        UpdateChecker.ReleaseManifest.ManifestAsset(name: assetName, sha256: lowerSHA)
    ])
    expect(manifestError(duplicateAsset).contains("重复资产"),
           "rejects manifests with duplicate entries for the downloaded asset")

    let badSHA = UpdateChecker.ReleaseManifest(version: "v1.2.0", assets: [
        UpdateChecker.ReleaseManifest.ManifestAsset(name: assetName, sha256: "1234")
    ])
    expect(manifestError(badSHA).contains("sha256 格式无效"),
           "rejects manifests with malformed sha256 values")
}

func testLatestInstallLogURLValidation() {
    let trustedTemporaryDirectory = URL(fileURLWithPath: "/tmp", isDirectory: true)
    let trustedLogPath = "/tmp/SnapAIUpdate-123/install.log"

    expect(UpdateChecker.latestInstallLogStatus(storedPath: nil,
                                                fileExists: { _ in true },
                                                trustedTemporaryDirectory: trustedTemporaryDirectory) == .noRecord,
           "reports missing install log path as no record")
    expect(UpdateChecker.latestInstallLogStatus(storedPath: nil,
                                                fileExists: { _ in true },
                                                trustedTemporaryDirectory: trustedTemporaryDirectory).diagnosticCode == "no-record",
           "install log status exposes a stable no-record diagnostic code")
    expect(UpdateChecker.latestInstallLogStatus(storedPath: nil,
                                                fileExists: { _ in true },
                                                trustedTemporaryDirectory: trustedTemporaryDirectory).recoverySuggestion.contains("重新检查更新"),
           "install log status explains how to recover from missing log records")
    expect(UpdateChecker.latestInstallLogStatus(storedPath: "  ",
                                                fileExists: { _ in true },
                                                trustedTemporaryDirectory: trustedTemporaryDirectory) == .noRecord,
           "reports blank install log path as no record")
    expect(UpdateChecker.latestInstallLogStatus(storedPath: "/tmp/snapai-install.log",
                                                fileExists: { _ in true },
                                                trustedTemporaryDirectory: trustedTemporaryDirectory) == .untrustedLocation("/tmp/snapai-install.log"),
           "rejects install logs outside SnapAI update directories")
    expect(UpdateChecker.latestInstallLogStatus(storedPath: "/tmp/snapai-install.log",
                                                fileExists: { _ in true },
                                                trustedTemporaryDirectory: trustedTemporaryDirectory).diagnosticCode == "untrusted-location",
           "install log status exposes a stable untrusted diagnostic code")
    expect(UpdateChecker.latestInstallLogStatus(storedPath: "/tmp/snapai-install.log",
                                                fileExists: { _ in true },
                                                trustedTemporaryDirectory: trustedTemporaryDirectory).recoverySuggestion.contains("不受信任"),
           "install log status explains untrusted paths")
    expect(UpdateChecker.latestInstallLogStatus(storedPath: "/tmp/SnapAIUpdate-123/other.log",
                                                fileExists: { _ in true },
                                                trustedTemporaryDirectory: trustedTemporaryDirectory) == .untrustedLocation("/tmp/SnapAIUpdate-123/other.log"),
           "rejects unexpected install log filenames")
    expect(UpdateChecker.latestInstallLogStatus(storedPath: trustedLogPath,
                                                fileExists: { _ in false },
                                                trustedTemporaryDirectory: trustedTemporaryDirectory) == .missing(trustedLogPath),
           "reports trusted but missing install logs as expired")
    expect(UpdateChecker.latestInstallLogStatus(storedPath: trustedLogPath,
                                                fileExists: { _ in false },
                                                trustedTemporaryDirectory: trustedTemporaryDirectory).diagnosticPath == trustedLogPath,
           "install log status keeps the path for shareable diagnostics")
    expect(UpdateChecker.latestInstallLogStatus(storedPath: trustedLogPath,
                                                fileExists: { _ in false },
                                                trustedTemporaryDirectory: trustedTemporaryDirectory).recoverySuggestion.contains("临时安装日志已不存在"),
           "install log status explains expired temporary logs")
    expect(UpdateChecker.latestInstallLogStatus(storedPath: " \(trustedLogPath) ",
                                                fileExists: { _ in true },
                                                trustedTemporaryDirectory: trustedTemporaryDirectory) == .available(URL(fileURLWithPath: trustedLogPath)),
           "accepts existing trusted SnapAI install logs")
    expect(UpdateChecker.latestInstallLogStatus(storedPath: " \(trustedLogPath) ",
                                                fileExists: { _ in true },
                                                trustedTemporaryDirectory: trustedTemporaryDirectory).diagnosticCode == "available",
           "install log status exposes a stable available diagnostic code")
    expect(UpdateChecker.latestInstallLogStatus(storedPath: " \(trustedLogPath) ",
                                                fileExists: { _ in true },
                                                trustedTemporaryDirectory: trustedTemporaryDirectory).recoverySuggestion.contains("显示安装日志"),
           "install log status explains how to inspect available logs")

    expect(UpdateChecker.latestInstallLogURL(storedPath: nil, fileExists: { _ in true }) == nil,
           "rejects missing install log path")
    expect(UpdateChecker.latestInstallLogURL(storedPath: "  ", fileExists: { _ in true }) == nil,
           "rejects blank install log path")
    expect(UpdateChecker.latestInstallLogURL(storedPath: trustedLogPath,
                                             fileExists: { _ in false },
                                             trustedTemporaryDirectory: trustedTemporaryDirectory) == nil,
           "rejects missing install log file")
    expect(UpdateChecker.latestInstallLogURL(storedPath: " /tmp/snapai-install.log ",
                                             fileExists: { _ in true },
                                             trustedTemporaryDirectory: trustedTemporaryDirectory) == nil,
           "rejects untrusted install log file")
    expect(UpdateChecker.latestInstallLogURL(storedPath: " \(trustedLogPath) ",
                                             fileExists: { _ in true },
                                             trustedTemporaryDirectory: trustedTemporaryDirectory)?.path == trustedLogPath,
           "trims and accepts existing install log path")
}

func testInstallLogCommandSubtitleRedactsUserPaths() {
    expect(InstallLogCommand.subtitle(for: nil) == InstallLogCommand.missingSubtitle,
           "install log command explains missing logs")
    expect(InstallLogCommand.subtitle(for: .noRecord) == InstallLogCommand.missingSubtitle,
           "install log status subtitle explains missing logs")
    expect(InstallLogCommand.subtitle(for: .missing("/tmp/SnapAIUpdate-123/install.log")).contains("已过期"),
           "install log status subtitle explains expired temporary logs")
    let untrustedSubtitle = InstallLogCommand.subtitle(for: .untrustedLocation("/Users/alice/Library/Logs/snapai-install.log"))
    expect(untrustedSubtitle.contains("不受信任"),
           "install log status subtitle explains untrusted paths")
    expect(untrustedSubtitle.contains("/Users/[user]/Library/Logs/snapai-install.log"),
           "install log status subtitle redacts untrusted user paths")
    expect(!untrustedSubtitle.contains("/Users/alice"),
           "install log status subtitle does not expose raw untrusted user paths")
    let subtitle = InstallLogCommand.subtitle(for: URL(fileURLWithPath: "/Users/alice/Library/Logs/snapai-install.log"))
    expect(subtitle == "/Users/[user]/Library/Logs/snapai-install.log",
           "install log command subtitle hides user names")
    expect(!subtitle.contains("/Users/alice"),
           "install log command subtitle does not expose raw user paths")
}

func testDesignatedRequirementParsing() {
    let output = """
    Executable=/Applications/SnapAI.app/Contents/MacOS/SnapAI
    Identifier=com.snapai.app
    designated => identifier "com.snapai.app" and certificate leaf = H"547f9e9ccbac459f1ae9db2644e819edeb2e766e"
    """
    expect(
        UpdateChecker.designatedRequirementLine(from: output) == "identifier \"com.snapai.app\" and certificate leaf = H\"547f9e9ccbac459f1ae9db2644e819edeb2e766e\"",
        "parses designated requirement from codesign output"
    )
}

func testPermissionDiagnosticsFormatting() {
    expect(PermissionHealthSnapshot.quarantineSummary(fromXattrOutput: nil) == "absent",
           "reports missing quarantine attribute")
    expect(PermissionHealthSnapshot.quarantineSummary(fromXattrOutput: "\n") == "absent",
           "treats empty quarantine output as absent")
    let quarantine = PermissionHealthSnapshot.quarantineSummary(fromXattrOutput: "0081;65f00000;Safari;")
    expect(quarantine == "present (0081;65f00000;Safari;)", "formats present quarantine attribute")
    expect(PermissionHealthSnapshot.shareablePath("/Users/alice/Applications/SnapAI.app",
                                                  homeDirectory: "/Users/alice") == "~/Applications/SnapAI.app",
           "collapses current home directory paths in shareable diagnostics")
    expect(PermissionHealthSnapshot.shareablePath("/Users/bob/Applications/SnapAI.app",
                                                  homeDirectory: "/Users/alice") == "/Users/[user]/Applications/SnapAI.app",
           "redacts other user directory names in shareable diagnostics")
    expect(PermissionHealthSnapshot.shareablePath("/Applications/SnapAI.app",
                                                  homeDirectory: "/Users/alice") == "/Applications/SnapAI.app",
           "keeps system application paths readable in shareable diagnostics")
    expect(PermissionHealthSnapshot.shareablePath("  ",
                                                  homeDirectory: "/Users/alice") == "none",
           "normalizes blank paths in shareable diagnostics")

    let snapshot = PermissionHealthSnapshot(appVersion: "1.2.0",
                                            macOSVersion: "macOS 14",
                                            bundleID: "com.snapai.app",
                                            installPath: "/Users/bob/Applications/SnapAI.app",
                                            accessibilityGranted: true,
                                            screenCaptureGranted: false,
                                            launchAtLogin: true,
                                            showDockIcon: false,
                                            installDirectoryWritable: true,
                                            quarantineStatus: "absent",
                                            latestInstallLogPath: "/Users/bob/Library/Logs/snapai-install.log",
                                            latestInstallLogAvailable: true,
                                            latestInstallLogStatus: "available",
                                            latestInstallLogRecoverySuggestion: "可通过命令面板或权限健康中心显示安装日志",
                                            signingSummary: "CDHash=abc",
                                            hotKeyFailures: ["⌥A failed"],
                                            activeModel: "OpenAI / gpt-4o-mini",
                                            providerCount: 2,
                                            enabledProviderCount: 2,
                                            requestReadyProviderCount: 1,
                                            activeProviderRequestReady: true,
                                            activeProviderRequestStatus: "ready",
                                            activeProviderRequestStatusText: "可请求",
                                            activeProviderRequestRecoverySuggestion: "无需处理",
                                            unavailableRequestReasonSummary: "missing-api-key=1",
                                            unavailableRequestRecoverySummary: "missing-api-key=1: 在 AI 设置中重新填写 API Key",
                                            apiKeyConfiguredProviderCount: 1,
                                            enabledProviderMissingAPIKeyCount: 1,
                                            textCaptureStatus: "state=no-selection, accessibility=missing, preferAX=yes, frontmostApp=Pages, capturedChars=0, recovery=授予辅助功能权限后重试; 也可打开快捷提问",
                                            writeBackStatus: "state=available",
                                            privacyPreviewEnabled: true,
                                            redactionEnabled: true,
                                            redactionRuleCount: 3,
                                            invalidRedactionRuleCount: 1,
                                            historyContentStorage: .metadataOnly,
                                            contextProfileCount: 3,
                                            usableContextProfileCount: 1,
                                            activeContextProfileName: "项目 A",
                                            activeContextCharacterCount: 42,
                                            globalSystemPromptCharacterCount: 18,
                                            effectiveSystemPromptCharacterCount: 96,
                                            workModeTitle: "隐私模式",
                                            workModeDetail: "发送前确认、本地脱敏,历史仅保存元信息。")
    let diagnostics = snapshot.diagnosticText
    expect(diagnostics.contains("Install Path: /Users/[user]/Applications/SnapAI.app"), "redacts user name in install path")
    expect(diagnostics.contains("Install Directory Writable: yes"), "includes install directory writability")
    expect(diagnostics.contains("Quarantine: absent"), "includes quarantine status")
    expect(diagnostics.contains("Latest Install Log: /Users/[user]/Library/Logs/snapai-install.log"), "redacts user name in latest install log path")
    expect(diagnostics.contains("Latest Install Log Status: available"), "includes latest install log status")
    expect(diagnostics.contains("Latest Install Log Recovery: 可通过命令面板或权限健康中心显示安装日志"),
           "includes latest install log recovery suggestion")
    expect(diagnostics.contains("Latest Install Log Available: yes"), "includes latest install log availability")
    expect(!diagnostics.contains("/Users/bob"), "permission diagnostics does not expose user home directory names")
    expect(diagnostics.contains("Work Mode: 隐私模式"), "includes current work mode")
    expect(diagnostics.contains("Work Mode Detail: 发送前确认、本地脱敏,历史仅保存元信息。"),
           "includes current work mode detail")
    expect(diagnostics.contains("Enabled Providers: 2"), "includes enabled provider count")
    expect(diagnostics.contains("Request Ready Providers: 1/2"), "includes request-ready provider count")
    expect(diagnostics.contains("Active Provider Request Ready: yes"), "includes active provider request readiness")
    expect(diagnostics.contains("Active Provider Request Status: ready"), "includes active provider request status")
    expect(diagnostics.contains("Active Provider Request Recovery: 无需处理"), "includes active provider request recovery")
    expect(diagnostics.contains("Unavailable Request Reasons: missing-api-key=1"), "includes unavailable request reason summary")
    expect(diagnostics.contains("Unavailable Request Recovery: missing-api-key=1: 在 AI 设置中重新填写 API Key"),
           "includes unavailable request recovery summary")
    expect(diagnostics.contains("API Keys: 1/2 configured; enabled missing 1"), "includes keychain api key health counts")
    expect(diagnostics.contains("Text Capture: state=no-selection, accessibility=missing, preferAX=yes, frontmostApp=Pages, capturedChars=0"),
           "includes recent text capture status")
    expect(diagnostics.contains("Privacy Preview: enabled"), "includes privacy preview state")
    expect(diagnostics.contains("Local Redaction: enabled"), "includes local redaction state")
    expect(diagnostics.contains("Redaction Rules: 3 (invalid 1)"), "includes redaction rule health")
    expect(diagnostics.contains("History Content Storage: 仅元信息"), "includes history content storage mode")
    expect(diagnostics.contains("Context Profiles: 3 (usable 1)"), "includes context profile health")
    expect(diagnostics.contains("Active Context: set"), "reports active context presence")
    expect(diagnostics.contains("Active Context Name Characters: 4"), "reports active context name length")
    expect(diagnostics.contains("Active Context Characters: 42"), "includes active context length")
    expect(diagnostics.contains("Global System Prompt Characters: 18"), "includes base system prompt length")
    expect(diagnostics.contains("Effective System Prompt Characters: 96"), "includes effective system prompt length")
    expect(!diagnostics.contains("项目 A"), "permission diagnostics does not expose context profile name")
    expect(!diagnostics.contains("术语: SnapAI"), "permission diagnostics does not expose context content")
    expect(!diagnostics.contains("基础提示"), "permission diagnostics does not expose system prompt content")
    expect(diagnostics.contains("HotKey Failures: ⌥A failed"), "includes hotkey failures")
    expect(diagnostics.contains("Recovery Suggestion Count: 6"),
           "full permission diagnostics include recovery suggestion count")
    expect(diagnostics.contains("Recovery Suggestion Status: 6 条建议"),
           "full permission diagnostics include recovery suggestion status")
    expect(diagnostics.contains("Recovery Suggestions: 屏幕录制: 在系统设置中允许 SnapAI 使用屏幕录制,然后重试截图提问"),
           "full permission diagnostics include recovery suggestions")
    expect(diagnostics.contains("API Key: 在 AI 设置中补齐启用供应商的 API Key"),
           "full permission diagnostics include api key recovery suggestion")
    expect(diagnostics.contains("取词: 授予辅助功能权限后重试; 也可打开快捷提问"),
           "full permission diagnostics include text capture recovery suggestion")

    let brief = snapshot.briefDiagnosticText
    expect(brief.contains("SnapAI Diagnostics Summary"), "brief permission diagnostics has a distinct heading")
    expect(brief.contains("Install Path: /Users/[user]/Applications/SnapAI.app"),
           "brief permission diagnostics redacts user name in install path")
    expect(brief.contains("Latest Install Log Status: available"),
           "brief permission diagnostics includes latest install log status without path")
    expect(!brief.contains("Latest Install Log Recovery:"),
           "brief permission diagnostics omits verbose install log recovery details")
    expect(brief.contains("AI Request: 可请求 1/2 个启用供应商"),
           "brief permission diagnostics includes request readiness summary")
    expect(brief.contains("API Key Health: 1 个启用供应商缺少 API Key"),
           "brief permission diagnostics includes api key health summary")
    expect(brief.contains("Text Capture: state=no-selection"),
           "brief permission diagnostics includes text capture status")
    expect(brief.contains("Work Mode: 隐私模式 - 发送前确认、本地脱敏,历史仅保存元信息。"),
           "brief permission diagnostics includes work mode summary")
    expect(brief.contains("Privacy: preview enabled, redaction enabled, invalid rules 1/3"),
           "brief permission diagnostics includes privacy summary")
    expect(brief.contains("Context: 1/3 usable; active set; effective prompt 96 chars"),
           "brief permission diagnostics includes safe context counts")
    expect(brief.contains("Recovery Suggestion Count: 6"),
           "brief permission diagnostics include recovery suggestion count")
    expect(brief.contains("Recovery Suggestion Status: 6 条建议"),
           "brief permission diagnostics include recovery suggestion status")
    expect(brief.contains("Recovery Suggestions: 屏幕录制: 在系统设置中允许 SnapAI 使用屏幕录制,然后重试截图提问"),
           "brief permission diagnostics include recovery suggestions")
    expect(brief.contains("API Key: 在 AI 设置中补齐启用供应商的 API Key"),
           "brief permission diagnostics include api key recovery suggestion")
    expect(brief.contains("取词: 授予辅助功能权限后重试; 也可打开快捷提问"),
           "brief permission diagnostics include text capture recovery suggestion")
    expect(!brief.contains("Latest Install Log:"),
           "brief permission diagnostics omits verbose install log details")
    expect(!brief.contains("项目 A"),
           "brief permission diagnostics does not expose context profile names")
    expect(brief.count < diagnostics.count,
           "brief permission diagnostics is shorter than full diagnostics")

    expect(PermissionHealthSnapshot.diagnosticField("recovery", in: snapshot.textCaptureStatus) == "授予辅助功能权限后重试; 也可打开快捷提问",
           "permission diagnostics can extract recovery guidance from structured status summaries")
    let recoverySuggestions = snapshot.recoverySuggestions
    expect(snapshot.recoverySuggestionCount == 6,
           "permission health snapshot exposes recovery suggestion count")
    expect(snapshot.recoverySuggestionStatusLine == "6 条建议",
           "permission health snapshot exposes compact recovery suggestion status")
    expect(recoverySuggestions.contains(PermissionHealthRecoverySuggestion(title: "屏幕录制",
                                                                           detail: "在系统设置中允许 SnapAI 使用屏幕录制,然后重试截图提问")),
           "permission health suggestions include screen recording recovery")
    expect(recoverySuggestions.contains(PermissionHealthRecoverySuggestion(title: "API Key",
                                                                           detail: "在 AI 设置中补齐启用供应商的 API Key")),
           "permission health suggestions include api key recovery")
    expect(recoverySuggestions.contains(PermissionHealthRecoverySuggestion(title: "备用供应商",
                                                                           detail: "missing-api-key=1: 在 AI 设置中重新填写 API Key")),
           "permission health suggestions include fallback provider recovery")
    expect(recoverySuggestions.contains(PermissionHealthRecoverySuggestion(title: "取词",
                                                                           detail: "授予辅助功能权限后重试; 也可打开快捷提问")),
           "permission health suggestions surface recent text capture recovery")
    let suggestionText = recoverySuggestions.map { "\($0.title): \($0.detail)" }.joined(separator: "\n")
    expect(!suggestionText.contains("/Users/bob"),
           "permission health suggestions do not expose user paths")
    expect(!suggestionText.contains("sk-live-secret-value-1234567890"),
           "permission health suggestions do not expose api keys")
    let clipboardSuggestions = snapshot.recoverySuggestionClipboardText
    expect(clipboardSuggestions.hasPrefix("SnapAI 修复建议\n"),
           "permission health suggestion clipboard text is self-describing")
    expect(clipboardSuggestions.contains("- 屏幕录制: 在系统设置中允许 SnapAI 使用屏幕录制,然后重试截图提问"),
           "permission health suggestion clipboard text uses readable bullet lines")
    expect(clipboardSuggestions.contains("- API Key: 在 AI 设置中补齐启用供应商的 API Key"),
           "permission health suggestion clipboard text includes api key recovery")
    expect(clipboardSuggestions.contains("- 取词: 授予辅助功能权限后重试; 也可打开快捷提问"),
           "permission health suggestion clipboard text includes text capture recovery")
    expect(!clipboardSuggestions.contains("/Users/bob"),
           "permission health suggestion clipboard text does not expose user paths")
    expect(!clipboardSuggestions.contains("sk-live-secret-value-1234567890"),
           "permission health suggestion clipboard text does not expose api keys")
    let healthySnapshot = PermissionHealthSnapshot(appVersion: "1.2.0",
                                                   macOSVersion: "macOS 14",
                                                   bundleID: "com.snapai.app",
                                                   installPath: "/Applications/SnapAI.app",
                                                   accessibilityGranted: true,
                                                   screenCaptureGranted: true,
                                                   launchAtLogin: true,
                                                   showDockIcon: true,
                                                   installDirectoryWritable: true,
                                                   quarantineStatus: "absent",
                                                   latestInstallLogPath: "none",
                                                   latestInstallLogAvailable: false,
                                                   latestInstallLogStatus: "no-record",
                                                   signingSummary: "CDHash=abc",
                                                   hotKeyFailures: [],
                                                   activeModel: "OpenAI / gpt-4o-mini",
                                                   providerCount: 1,
                                                   enabledProviderCount: 1,
                                                   requestReadyProviderCount: 1,
                                                   activeProviderRequestReady: true,
                                                   activeProviderRequestStatus: "ready",
                                                   activeProviderRequestStatusText: "可请求",
                                                   activeProviderRequestRecoverySuggestion: "无需处理",
                                                   unavailableRequestReasonSummary: "none",
                                                   unavailableRequestRecoverySummary: "none",
                                                   apiKeyConfiguredProviderCount: 1,
                                                   enabledProviderMissingAPIKeyCount: 0,
                                                   textCaptureStatus: "state=captured, recovery=无需处理",
                                                   writeBackStatus: "state=available",
                                                   privacyPreviewEnabled: true,
                                                   redactionEnabled: true,
                                                   redactionRuleCount: 1,
                                                   invalidRedactionRuleCount: 0)
    expect(healthySnapshot.recoverySuggestionClipboardText == "SnapAI 修复建议\n暂无需要处理的建议",
           "permission health suggestion clipboard text has a stable empty-state message")
    expect(healthySnapshot.recoverySuggestionCount == 0,
           "healthy permission health snapshot has no recovery suggestions")
    expect(healthySnapshot.recoverySuggestionStatusLine == "无需处理",
           "healthy permission health snapshot reports no required action")

    let recentAIRequestSnapshot = PermissionHealthSnapshot(appVersion: "1.2.0",
                                                           macOSVersion: "macOS 14",
                                                           bundleID: "com.snapai.app",
                                                           installPath: "/Applications/SnapAI.app",
                                                           accessibilityGranted: true,
                                                           screenCaptureGranted: true,
                                                           launchAtLogin: true,
                                                           showDockIcon: true,
                                                           installDirectoryWritable: true,
                                                           quarantineStatus: "absent",
                                                           latestInstallLogPath: "none",
                                                           latestInstallLogAvailable: false,
                                                           latestInstallLogStatus: "no-record",
                                                           signingSummary: "CDHash=abc",
                                                           hotKeyFailures: [],
                                                           activeModel: "LM Studio / local-chat",
                                                           providerCount: 2,
                                                           enabledProviderCount: 2,
                                                           requestReadyProviderCount: 2,
                                                           activeProviderRequestReady: true,
                                                           activeProviderRequestStatus: "ready",
                                                           activeProviderRequestStatusText: "可请求",
                                                           activeProviderRequestRecoverySuggestion: "无需处理",
                                                           unavailableRequestReasonSummary: "none",
                                                           unavailableRequestRecoverySummary: "none",
                                                           recentAIRequestStatus: "outcome=failed; fallback=cloud-confirmation-required, recoveryCode=fallback-cloud-confirmation-required, recovery=本地模型失败;如需改用云端模型请手动选择云端模型后重试, latest=LM Studio / local-chat -> 失败",
                                                           apiKeyConfiguredProviderCount: 2,
                                                           enabledProviderMissingAPIKeyCount: 0,
                                                           textCaptureStatus: "state=captured, recovery=无需处理",
                                                           writeBackStatus: "state=available",
                                                           privacyPreviewEnabled: true,
                                                           redactionEnabled: true,
                                                           redactionRuleCount: 1,
                                                           invalidRedactionRuleCount: 0)
    expect(recentAIRequestSnapshot.diagnosticText.contains("Recent AI Request: outcome=failed"),
           "permission diagnostics include the recent AI request status")
    expect(recentAIRequestSnapshot.briefDiagnosticText.contains("Recent AI Request: outcome=failed"),
           "brief permission diagnostics include the recent AI request status")
    expect(recentAIRequestSnapshot.recoverySuggestions == [
        PermissionHealthRecoverySuggestion(title: "最近 AI 请求",
                                           detail: "本地模型失败;如需改用云端模型请手动选择云端模型后重试")
    ], "permission health suggestions surface the recent AI request recovery")

    let pasteboardRecovery = "当前剪贴板内容过大或格式过多,为避免丢失用户剪贴板,已取消自动粘贴。请手动复制结果后粘贴。"
    let pasteboardProtectedSnapshot = PermissionHealthSnapshot(appVersion: "1.2.0",
                                                               macOSVersion: "macOS 14",
                                                               bundleID: "com.snapai.app",
                                                               installPath: "/Applications/SnapAI.app",
                                                               accessibilityGranted: true,
                                                               screenCaptureGranted: true,
                                                               launchAtLogin: true,
                                                               showDockIcon: true,
                                                               installDirectoryWritable: true,
                                                               quarantineStatus: "absent",
                                                               latestInstallLogPath: "none",
                                                               latestInstallLogAvailable: false,
                                                               latestInstallLogStatus: "no-record",
                                                               signingSummary: "CDHash=abc",
                                                               hotKeyFailures: [],
                                                               activeModel: "OpenAI / gpt-4o-mini",
                                                               providerCount: 1,
                                                               enabledProviderCount: 1,
                                                               requestReadyProviderCount: 1,
                                                               activeProviderRequestReady: true,
                                                               activeProviderRequestStatus: "ready",
                                                               activeProviderRequestStatusText: "可请求",
                                                               activeProviderRequestRecoverySuggestion: "无需处理",
                                                               unavailableRequestReasonSummary: "none",
                                                               unavailableRequestRecoverySummary: "none",
                                                               apiKeyConfiguredProviderCount: 1,
                                                               enabledProviderMissingAPIKeyCount: 0,
                                                               textCaptureStatus: "state=captured, recovery=无需处理",
                                                               writeBackStatus: "state=fallback-copied, operation=replace, copiedToPasteboard=no, recovery=\(pasteboardRecovery)",
                                                               privacyPreviewEnabled: true,
                                                               redactionEnabled: true,
                                                               redactionRuleCount: 1,
                                                               invalidRedactionRuleCount: 0)
    expect(pasteboardProtectedSnapshot.recoverySuggestionCount == 1,
           "permission health reports only the pasteboard-protected writeback suggestion")
    expect(pasteboardProtectedSnapshot.recoverySuggestions == [
        PermissionHealthRecoverySuggestion(title: "写回", detail: pasteboardRecovery)
    ], "permission health surfaces pasteboard safety recovery as the writeback suggestion")
    expect(pasteboardProtectedSnapshot.recoverySuggestionClipboardText.contains("- 写回: \(pasteboardRecovery)"),
           "permission recovery clipboard text includes pasteboard safety guidance")

    let lightweightSnapshot = PermissionHealthSnapshot.make(settings: AppSettings(),
                                                            hotKeyFailures: [],
                                                            textCaptureStatus: "none",
                                                            writeBackStatus: "none",
                                                            includeSigningSummary: false)
    expect(lightweightSnapshot.signingSummary == "未检查",
           "lightweight permission health snapshots skip signing inspection")
    expect(lightweightSnapshot.diagnosticText.contains("Signing: 未检查"),
           "full diagnostics expose skipped signing inspection state")
    expect(lightweightSnapshot.briefDiagnosticText.contains("Signing: 未检查"),
           "brief diagnostics expose skipped signing inspection state")

    expect(PermissionRecoveryCommand.title == "复制权限修复建议",
           "permission recovery command has a clear title")
    expect(PermissionRecoveryCommand.subtitle == "只复制权限健康中心当前建议",
           "permission recovery command explains the narrow copy scope")
    expect(PermissionRecoveryCommand.subtitle(statusLine: snapshot.recoverySuggestionStatusLine) == "当前: 6 条建议, 复制修复建议",
           "permission recovery command subtitle can include current suggestion status")
    expect(PermissionRecoveryCommand.subtitle(statusLine: healthySnapshot.recoverySuggestionStatusLine) == "当前: 无需处理, 复制修复建议",
           "permission recovery command subtitle can describe healthy state")
    expect(!PermissionRecoveryCommand.subtitle(statusLine: "路径 /Users/alice/token sk-live-secret-value-1234567890").contains("/Users/alice"),
           "permission recovery command subtitle redacts user paths")
    expect(!PermissionRecoveryCommand.subtitle(statusLine: "路径 /Users/alice/token sk-live-secret-value-1234567890").contains("sk-live-secret-value-1234567890"),
           "permission recovery command subtitle redacts secrets")
    expect(PermissionRecoveryCommand.systemImage == "lightbulb",
           "permission recovery command uses a suggestion icon")
    expect(CommandPaletteMatcher.matches(title: PermissionRecoveryCommand.title,
                                         subtitle: PermissionRecoveryCommand.subtitle,
                                         keywords: PermissionRecoveryCommand.keywords,
                                         query: "修复 建议"),
           "permission recovery command is searchable by Chinese recovery intent")
    expect(CommandPaletteMatcher.matches(title: PermissionRecoveryCommand.title,
                                         subtitle: PermissionRecoveryCommand.subtitle,
                                         keywords: PermissionRecoveryCommand.keywords,
                                         query: "recovery suggestions"),
           "permission recovery command is searchable by English recovery intent")

    let unsafeSnapshot = PermissionHealthSnapshot(appVersion: "1.2.0",
                                                  macOSVersion: "macOS 14",
                                                  bundleID: "com.snapai.app",
                                                  installPath: "/Users/alice/Applications/SnapAI.app",
                                                  accessibilityGranted: true,
                                                  screenCaptureGranted: true,
                                                  launchAtLogin: false,
                                                  showDockIcon: true,
                                                  installDirectoryWritable: true,
                                                  quarantineStatus: "0081;\norigin=/Users/alice/Downloads/SnapAI.zip",
                                                  latestInstallLogPath: "/Users/alice/Library/Logs/snapai-install.log",
                                                  latestInstallLogAvailable: true,
                                                  signingSummary: "Authority=Developer\nRequirement=/Users/alice/cert\nAuthorization: Bearer sk-live-secret-value-1234567890",
                                                  hotKeyFailures: ["动作 sk-live-secret-value-1234567890\n注册失败"],
                                                  activeModel: "OpenAI / gpt-4o-mini\napi_key=sk-live-secret-value-1234567890 / /Users/alice/model",
                                                  providerCount: 1,
                                                  textCaptureStatus: "frontmostApp=/Users/alice/Secret.app\nkey=sk-live-secret-value-1234567890",
                                                  writeBackStatus: "target=/Users/alice/Documents/input.txt\nsecret=sk-live-secret-value-1234567890")
    let unsafeDiagnostics = unsafeSnapshot.diagnosticText
    let unsafeBrief = unsafeSnapshot.briefDiagnosticText
    expect(!unsafeDiagnostics.contains("sk-live-secret-value-1234567890"),
           "permission diagnostics redacts secrets from free-form diagnostic fields")
    expect(!unsafeDiagnostics.contains("/Users/alice"),
           "permission diagnostics redacts user paths from free-form diagnostic fields")
    expect(!unsafeDiagnostics.contains("api_key=sk-"),
           "permission diagnostics redacts api_key fragments")
    expect(unsafeDiagnostics.contains("/Users/[user]/Downloads/SnapAI.zip"),
           "permission diagnostics keeps useful redacted quarantine path suffixes")
    expect(unsafeDiagnostics.contains("Authorization: Bearer [REDACTED]"),
           "permission diagnostics keeps sanitized signing error context")
    expect(unsafeDiagnostics.contains("HotKey Failures: 动作 [REDACTED_KEY] 注册失败"),
           "permission diagnostics flattens and sanitizes hotkey failures")
    expect(!unsafeBrief.contains("sk-live-secret-value-1234567890"),
           "brief permission diagnostics redacts secrets from free-form diagnostic fields")
    expect(!unsafeBrief.contains("/Users/alice"),
           "brief permission diagnostics redacts user paths from free-form diagnostic fields")
    expect(unsafeBrief.contains("Authorization: Bearer [REDACTED]"),
           "brief permission diagnostics keeps sanitized signing error context")
    expect(unsafeBrief.contains("Recovery Suggestions:"),
           "brief permission diagnostics keeps actionable recovery suggestions")
    expect(!unsafeBrief.contains("sk-live-secret-value-1234567890"),
           "brief permission recovery suggestions redact secrets")
    expect(!unsafeBrief.contains("/Users/alice"),
           "brief permission recovery suggestions redact user paths")
    expect(!unsafeSnapshot.recoverySuggestionClipboardText.contains("sk-live-secret-value-1234567890"),
           "permission health suggestion clipboard text redacts unsafe secrets")
    expect(!unsafeSnapshot.recoverySuggestionClipboardText.contains("/Users/alice"),
           "permission health suggestion clipboard text redacts unsafe user paths")
}

func testPermissionDiagnosticsReportsAPIKeyHealth() {
    let settings = AppSettings()
    var ready = AIProvider(name: "Ready", apiProtocol: .openAI,
                           baseURL: "https://ready.test/v1",
                           apiKey: "sk-live-secret-value-1234567890",
                           models: [AIModelEntry(name: "ready-model", enabled: true)])
    ready.isEnabled = true
    var missing = AIProvider(name: "Missing", apiProtocol: .openAI,
                             baseURL: "https://missing.test/v1",
                             apiKey: " \n ",
                             models: [AIModelEntry(name: "missing-model", enabled: true)])
    missing.isEnabled = true
    var disabled = AIProvider(name: "Disabled", apiProtocol: .openAI,
                              baseURL: "https://disabled.test/v1",
                              apiKey: "",
                              models: [AIModelEntry(name: "disabled-model", enabled: true)])
    disabled.isEnabled = false
    var noEnabledModels = AIProvider(name: "No Models", apiProtocol: .openAI,
                                     baseURL: "https://nomodels.test/v1",
                                     apiKey: "",
                                     models: [AIModelEntry(name: "disabled-model", enabled: false)])
    noEnabledModels.isEnabled = true
    settings.providers = [ready, missing, disabled, noEnabledModels]

    let health = PermissionHealthSnapshot.apiKeyHealth(settings: settings)
    expect(health.configuredProviderCount == 1,
           "permission diagnostics counts providers with configured api keys")
    expect(health.enabledProviderMissingCount == 1,
           "permission diagnostics only flags enabled providers with enabled models and missing api keys")
    expect(health.statusLine == "1 个启用供应商缺少 API Key",
           "permission diagnostics builds api key health status text")
    expect(health.detailLine == "1/4 已配置 · 启用但缺失 1",
           "permission diagnostics builds api key health detail text")

    settings.providers = []
    let emptyHealth = PermissionHealthSnapshot.apiKeyHealth(settings: settings)
    expect(emptyHealth.statusLine == "尚未配置供应商",
           "permission diagnostics explains missing provider configuration in api key health")
    expect(emptyHealth.detailLine == "0/0 已配置 · 启用但缺失 0",
           "permission diagnostics builds stable empty api key health detail text")

    ready.apiKey = "key"
    missing.apiKey = "key2"
    settings.providers = [ready, missing]
    let configuredHealth = PermissionHealthSnapshot.apiKeyHealth(settings: settings)
    expect(configuredHealth.statusLine == "2/2 个供应商已配置",
           "permission diagnostics reports all api keys configured")
    expect(configuredHealth.detailLine == "2/2 已配置 · 启用但缺失 0",
           "permission diagnostics reports all configured api key detail text")
}

func testPermissionDiagnosticsReportsWorkMode() {
    let settings = AppSettings()
    settings.applyWorkMode(.privacy)

    let privacySnapshot = PermissionHealthSnapshot.make(settings: settings,
                                                        hotKeyFailures: [],
                                                        writeBackStatus: "none")
    expect(privacySnapshot.workModeTitle == "隐私模式",
           "permission diagnostics reports the matched work mode")
    expect(privacySnapshot.workModeDetail == WorkModePreset.privacy.summary,
           "permission diagnostics reports the matched work mode detail")
    expect(privacySnapshot.diagnosticText.contains("Work Mode: 隐私模式"),
           "full permission diagnostics includes matched work mode")
    expect(privacySnapshot.briefDiagnosticText.contains("Work Mode: 隐私模式"),
           "brief permission diagnostics includes matched work mode")

    settings.redactionEnabled = false
    let customSnapshot = PermissionHealthSnapshot.make(settings: settings,
                                                       hotKeyFailures: [],
                                                       writeBackStatus: "none")
    expect(customSnapshot.workModeTitle == "自定义模式",
           "permission diagnostics reports custom mode when behavior diverges from presets")
    expect(customSnapshot.workModeDetail.contains("偏离预设"),
           "permission diagnostics explains custom work mode mismatch")
}

func testPermissionDiagnosticsReportsRequestReadiness() {
    let settings = AppSettings()
    var ready = AIProvider(name: "Ready", apiProtocol: .openAI,
                           baseURL: "https://ready.test/v1",
                           apiKey: "key",
                           models: [AIModelEntry(name: "ready-model", enabled: true)])
    ready.id = "ready"
    ready.isEnabled = true
    var remoteHTTP = ready
    remoteHTTP.id = "remote-http"
    remoteHTTP.baseURL = "http://remote.example.test/v1"
    var missingKey = ready
    missingKey.id = "missing-key"
    missingKey.apiKey = ""
    var missingKeyAgain = ready
    missingKeyAgain.id = "missing-key-again"
    missingKeyAgain.apiKey = ""
    var disabled = ready
    disabled.id = "disabled"
    disabled.isEnabled = false
    settings.providers = [ready, remoteHTTP, missingKey, missingKeyAgain, disabled]
    settings.activeProviderID = ready.id
    settings.activeModel = "ready-model"

    var readiness = PermissionHealthSnapshot.requestReadiness(settings: settings)
    expect(readiness.enabledProviderCount == 4,
           "permission diagnostics counts enabled providers for request readiness")
    expect(readiness.readyProviderCount == 1,
           "permission diagnostics reuses router readiness for request-ready providers")
    expect(readiness.activeProviderReady,
           "permission diagnostics marks the active provider ready when it can request")
    expect(readiness.activeProvider == PermissionProviderRequestStatus(readiness: .ready),
           "permission diagnostics exposes structured active provider readiness")
    expect(readiness.activeProviderStatus == "ready",
           "permission diagnostics exposes the active provider readiness status")
    expect(readiness.unavailableReasonSummary == "missing-api-key=2; remote-http=1",
           "permission diagnostics summarizes unavailable provider reasons")
    expect(readiness.activeProviderRecoverySuggestion == "无需处理",
           "permission diagnostics exposes active provider recovery guidance")
    expect(readiness.unavailableRecoverySummary == "missing-api-key=2: 在 AI 设置中重新填写 API Key; remote-http=1: 远程端点请改用 HTTPS;HTTP 仅允许 localhost",
           "permission diagnostics summarizes recovery guidance in stable reason-code order")
    expect(readiness.statusLine == "可请求 1/4 个启用供应商",
           "permission diagnostics builds a compact request readiness status line")
    expect(readiness.detailLine == "1/4 可请求 · 当前可用 · missing-api-key=2: 在 AI 设置中重新填写 API Key; remote-http=1: 远程端点请改用 HTTPS;HTTP 仅允许 localhost",
           "permission diagnostics builds a detailed request readiness line")

    settings.activeProviderID = remoteHTTP.id
    settings.activeModel = "ready-model"
    readiness = PermissionHealthSnapshot.requestReadiness(settings: settings)
    expect(!readiness.activeProviderReady,
           "permission diagnostics marks the active provider unavailable when router readiness rejects it")
    expect(readiness.activeProviderStatus == "remote-http",
           "permission diagnostics reports why the active provider is unavailable")
    expect(readiness.activeProviderStatusText == "远程 HTTP 不安全",
           "permission diagnostics exposes localized active provider readiness text")
    expect(readiness.activeProviderRecoverySuggestion.contains("改用 HTTPS"),
           "permission diagnostics reports recovery guidance for the active provider")
    expect(readiness.statusLine == "可请求 1/4 个启用供应商 · 当前: 远程 HTTP 不安全",
           "permission diagnostics includes active provider issues in the compact status line")

    settings.activeProviderID = disabled.id
    settings.activeModel = "ready-model"
    readiness = PermissionHealthSnapshot.requestReadiness(settings: settings)
    expect(!readiness.activeProviderReady,
           "permission diagnostics does not hide a configured disabled active provider behind fallback")
    expect(readiness.activeProviderStatus == "disabled",
           "permission diagnostics reports configured disabled active providers")
    expect(readiness.activeProviderRecoverySuggestion.contains("启用该供应商"),
           "permission diagnostics suggests re-enabling configured disabled active providers")

    settings.activeProviderID = "missing-provider"
    readiness = PermissionHealthSnapshot.requestReadiness(settings: settings)
    expect(!readiness.activeProviderReady,
           "permission diagnostics does not hide a missing configured active provider behind fallback")
    expect(readiness.activeProviderStatus == "missing-active-provider",
           "permission diagnostics reports missing configured active providers")
    expect(readiness.activeProvider == .missingConfiguredActiveProvider,
           "permission diagnostics exposes structured missing configured active providers")
    expect(readiness.activeProviderStatusText == "当前供应商不存在",
           "permission diagnostics explains missing configured active provider ids")
    expect(readiness.activeProviderRecoverySuggestion.contains("重新选择供应商"),
           "permission diagnostics suggests reselecting missing configured active providers")

    let emptySettings = AppSettings()
    emptySettings.providers = []
    emptySettings.activeProviderID = ""
    emptySettings.activeModel = ""
    let emptyReadiness = PermissionHealthSnapshot.requestReadiness(settings: emptySettings)
    expect(emptyReadiness.statusLine == "没有启用供应商",
           "permission diagnostics explains when no providers are enabled")
    expect(emptyReadiness.detailLine == "0/0 可请求 · 当前: 未选择供应商 · 无异常",
           "permission diagnostics builds a stable empty request readiness detail line")
}

func testBaseURLNormalization() {
    expect(AIClient.normalizedBase("api.openai.com", proto: .openAI) == "https://api.openai.com/v1",
           "adds https and /v1")
    expect(AIClient.normalizedBase("https://api.deepseek.com/v1/chat/completions", proto: .openAI) == "https://api.deepseek.com/v1",
           "strips method suffix")
    expect(AIClient.normalizedBase("http://localhost:11434", proto: .openAI) == "http://localhost:11434/v1",
           "keeps local http")
}

func testAIClientEffectiveRuntimeParametersAreSanitized() {
    let settings = AppSettings()
    var provider = AIProvider(name: "Runtime", apiProtocol: .openAI,
                              baseURL: "https://runtime.test/v1",
                              apiKey: "key",
                              models: [AIModelEntry(name: "model")])
    provider.isEnabled = true
    provider.temperature = 9
    provider.maxTokens = AppSettings.importedMaxTokensRange.upperBound + 500
    provider.requestTimeout = 1
    settings.providers = [provider]
    settings.activeProviderID = provider.id
    settings.activeModel = "model"
    settings.temperature = .nan

    expect(AIClient.effectiveTemperature(settings: settings) == 1,
           "runtime clamps provider temperature overrides")
    expect(AIClient.effectiveMaxTokens(settings: settings) == AppSettings.importedMaxTokensRange.upperBound,
           "runtime clamps provider max tokens")
    expect(AIClient.effectiveTimeout(settings: settings) == AppSettings.importedRequestTimeoutRange.lowerBound,
           "runtime clamps low provider timeout")

    settings.providers[0].temperature = nil
    settings.providers[0].maxTokens = -10
    settings.providers[0].requestTimeout = .infinity

    expect(AIClient.effectiveTemperature(settings: settings) == 0.3,
           "runtime falls back to safe global temperature")
    expect(AIClient.effectiveMaxTokens(settings: settings) == AIClient.defaultMaxTokens,
           "runtime falls back from invalid max tokens")
    expect(AIClient.effectiveTimeout(settings: settings) == AIClient.defaultRequestTimeout,
           "runtime falls back from invalid timeout")

    var thinkingAction = AIAction()
    thinkingAction.thinkingMode = true
    thinkingAction.thinkingBudget = 8_000
    settings.providers[0].maxTokens = 2_048
    let thinkingBudget = AIClient.effectiveThinkingBudget(action: thinkingAction)
    expect(thinkingBudget == 8_000, "runtime preserves valid thinking budgets")
    expect(AIClient.effectiveMaxTokens(settings: settings,
                                       minimum: thinkingBudget + AIClient.thinkingOutputTokenMargin) == 9_024,
           "runtime raises max tokens to cover thinking budget plus output margin")

    let json = #"{"settingsSchemaVersion":2,"temperature":9,"providers":[]}"#.data(using: .utf8)!
    let decoded = try? JSONDecoder().decode(AppSettings.self, from: json)
    expect(decoded?.temperature == 1, "settings decode clamps global temperature")
}

func testAIClientStreamErrorParsing() {
    let openAIError: [String: Any] = [
        "error": [
            "message": "bad api key sk-live-secret-value-1234567890",
            "type": "invalid_request_error",
            "code": "invalid_api_key"
        ]
    ]
    let openAIMessage = AIClient.openAIStreamErrorMessage(from: openAIError) ?? ""
    expect(openAIMessage.contains("invalid_request_error"), "OpenAI stream error includes error type")
    expect(openAIMessage.contains("invalid_api_key"), "OpenAI stream error includes error code")
    expect(openAIMessage.contains("bad api key"), "OpenAI stream error includes useful message")
    expect(!openAIMessage.contains("sk-live-secret-value-1234567890"), "OpenAI stream error redacts API keys")

    let normalOpenAIChunk: [String: Any] = [
        "choices": [
            ["delta": ["content": "hello"]]
        ]
    ]
    expect(AIClient.openAIStreamErrorMessage(from: normalOpenAIChunk) == nil,
           "OpenAI normal delta chunks are not treated as errors")

    let anthropicError: [String: Any] = [
        "type": "error",
        "error": [
            "type": "overloaded_error",
            "message": "Overloaded"
        ]
    ]
    let anthropicMessage = AIClient.anthropicStreamErrorMessage(from: anthropicError) ?? ""
    expect(anthropicMessage.contains("overloaded_error"), "Anthropic stream error includes error type")
    expect(anthropicMessage.contains("Overloaded"), "Anthropic stream error includes message")

    let anthropicTopLevelError: [String: Any] = [
        "type": "error",
        "message": "Authorization: Bearer sk-live-secret-value-1234567890"
    ]
    let topLevelMessage = AIClient.anthropicStreamErrorMessage(from: anthropicTopLevelError) ?? ""
    expect(topLevelMessage.contains("[REDACTED"), "Anthropic top-level stream errors are sanitized")
    expect(!topLevelMessage.contains("sk-live-secret-value-1234567890"),
           "Anthropic top-level stream errors do not leak bearer secrets")

    let normalAnthropicChunk: [String: Any] = [
        "type": "content_block_delta",
        "delta": [
            "type": "text_delta",
            "text": "hello"
        ]
    ]
    expect(AIClient.anthropicStreamErrorMessage(from: normalAnthropicChunk) == nil,
           "Anthropic normal delta chunks are not treated as errors")

    let longOpenAIError: [String: Any] = [
        "error": [
            "message": String(repeating: "错误详情", count: 120)
        ]
    ]
    let longMessage = AIClient.openAIStreamErrorMessage(from: longOpenAIError) ?? ""
    expect(longMessage.count <= 303, "stream error messages are length-limited for diagnostics")
    expect(longMessage.contains("..."), "long stream error messages are truncated explicitly")
}

func testAIClientResponseErrorBodySanitization() {
    let openAIJSON = """
    {"error":{"message":"bad api key sk-live-secret-value-1234567890","type":"invalid_request_error","code":"invalid_api_key"}}
    """
    let openAIMessage = AIClient.sanitizedResponseBody(openAIJSON, limit: 1_000)
    expect(openAIMessage.contains("invalid_request_error"), "response error body extracts OpenAI error type")
    expect(openAIMessage.contains("invalid_api_key"), "response error body extracts OpenAI error code")
    expect(openAIMessage.contains("bad api key"), "response error body extracts OpenAI error message")
    expect(!openAIMessage.contains("sk-live-secret-value-1234567890"),
           "response error body redacts OpenAI JSON keys")
    expect(!openAIMessage.contains("{\"error\""),
           "response error body summarizes structured OpenAI JSON instead of exposing raw payload")

    let anthropicJSON = """
    {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}
    """
    let anthropicMessage = AIClient.sanitizedResponseBody(anthropicJSON, limit: 1_000)
    expect(anthropicMessage.contains("overloaded_error"), "response error body extracts Anthropic error type")
    expect(anthropicMessage.contains("Overloaded"), "response error body extracts Anthropic error message")

    let topLevelJSON = """
    {"type":"invalid_request_error","message":"failed at /Users/alice/Projects/SnapAI/build.log","param":"model"}
    """
    let topLevelMessage = AIClient.sanitizedResponseBody(topLevelJSON, limit: 1_000)
    expect(topLevelMessage.contains("invalid_request_error"), "response error body extracts top-level error type")
    expect(topLevelMessage.contains("model"), "response error body extracts top-level error parameter")
    expect(!topLevelMessage.contains("/Users/alice"), "response error body redacts paths in top-level JSON")

    let body = """
    HTTP 401
    Authorization: Bearer sk-live-secret-value-1234567890
    {"api_key":"sk-json-secret-value-1234567890","message":"failed"}
    log: /Users/alice/Library/Logs/snapai.log
    """
    let sanitized = AIClient.sanitizedResponseBody(body, limit: 1_000)
    expect(sanitized.contains("[REDACTED"), "response error body sanitizer redacts sensitive fragments")
    expect(!sanitized.contains("sk-live-secret-value-1234567890"), "response error body sanitizer redacts bearer keys")
    expect(!sanitized.contains("sk-json-secret-value-1234567890"), "response error body sanitizer redacts JSON keys")
    expect(!sanitized.contains("/Users/alice"), "response error body sanitizer redacts local user paths")
    expect(sanitized.contains("/Users/[user]/Library/Logs/snapai.log"),
           "response error body sanitizer keeps useful path suffix")
    expect(!sanitized.contains("\n"), "response error body sanitizer flattens messages for UI")

    expect(AIClient.sanitizedResponseBody(" \n ", fallback: "empty") == "empty",
           "response error body sanitizer uses fallback for blank bodies")

    let long = AIClient.sanitizedResponseBody(String(repeating: "失败详情", count: 80), limit: 40)
    expect(long.count <= 43, "response error body sanitizer respects explicit limits")
    expect(long.contains("..."), "response error body sanitizer marks truncation")

    let arrayError = AIClient.sanitizedResponseBody(#"[{"message":"bad sk-live-secret-value-1234567890"}]"#,
                                                    limit: 1_000)
    expect(arrayError.contains("[REDACTED_KEY]"), "response error body sanitizer redacts JSON array fallbacks")
    expect(!arrayError.contains("sk-live-secret-value-1234567890"),
           "response error body sanitizer does not leak secrets in JSON array fallbacks")
}

func testPromptRender() {
    var action = AIAction()
    action.prompt = "翻译: {{lang}}\n{{text}}"
    action.isTranslation = true
    action.targetLanguage = .english
    expect(action.render(text: "你好") == "翻译: 翻译成自然流畅的英语\n你好", "renders text and language placeholders")
}

func testActionPipelineDiagnostic() {
    let settings = AppSettings()
    settings.applyWorkMode(.privacy)
    var action = AIAction.defaults()[2]
    action.saveHistory = false
    action.providerID = "local-provider"
    action.modelOverride = "local-chat"

    let diagnostic = ActionPipelineDiagnostic.make(action: action,
                                                   settings: settings,
                                                   hasImage: true)
    expect(diagnostic.inputPolicy == "text+image",
           "pipeline diagnostic records image input")
    expect(diagnostic.privacyPolicy == "preview+local-redaction+no-history",
           "pipeline diagnostic summarizes privacy stages")
    expect(diagnostic.outputPolicy == "replace-confirmation",
           "pipeline diagnostic records replacement confirmation output")
    expect(diagnostic.modelPolicy == "action-override",
           "pipeline diagnostic records action model overrides")
    expect(diagnostic.summaryLines.contains("Pipeline Privacy: preview+local-redaction+no-history"),
           "pipeline diagnostic renders shareable summary lines")

    action.providerID = nil
    action.modelOverride = nil
    action.saveHistory = true
    let localFirst = ActionPipelineDiagnostic.make(action: action,
                                                  settings: settings,
                                                  hasImage: false)
    expect(localFirst.modelPolicy == "auto-route-local-first",
           "pipeline diagnostic records privacy-mode local-first routing")
    expect(localFirst.privacyPolicy.contains("history-metadata-only"),
           "pipeline diagnostic records metadata-only history")
}

func testAIActionSanitizesImportedConfiguration() {
    var action = AIAction()
    action.id = "duplicate-action"
    action.name = String(repeating: "动作", count: 80)
    action.icon = String(repeating: "i", count: AIAction.maxIconLength + 10)
    action.group = String(repeating: "分组", count: 80)
    action.prompt = String(repeating: "p", count: AIAction.maxPromptLength + 100)
    action.thinkingBudget = -100
    action.providerID = " provider "
    action.modelOverride = " model "

    var duplicate = action
    duplicate.name = "Second"
    duplicate.thinkingBudget = AIAction.thinkingBudgetRange.upperBound + 100

    let sanitized = AppSettings.sanitizedImportedActions([action, duplicate])
    expect(sanitized.count == 2, "keeps imported actions after sanitizing")
    expect(Set(sanitized.map(\.id)).count == 2, "assigns unique action ids")
    expect(sanitized.first?.name.count == AIAction.maxNameLength, "caps action names")
    expect(sanitized.first?.icon.count == AIAction.maxIconLength, "caps action icons")
    expect(sanitized.first?.group.count == AIAction.maxGroupLength, "caps action groups")
    expect(sanitized.first?.prompt.count == AIAction.maxPromptLength, "caps action prompts")
    expect(sanitized.first?.thinkingBudget == AIAction.thinkingBudgetRange.lowerBound,
           "clamps low thinking budgets")
    expect(sanitized.dropFirst().first?.thinkingBudget == AIAction.thinkingBudgetRange.upperBound,
           "clamps high thinking budgets")
    expect(sanitized.first?.providerID == "provider", "trims action provider ids")
    expect(sanitized.first?.modelOverride == "model", "trims action model overrides")
    action.modelOverride = String(repeating: "m", count: AppSettings.importedModelNameLimit + 20)
    expect(AppSettings.sanitizedImportedActions([action]).first?.modelOverride?.count == AppSettings.importedModelNameLimit,
           "caps action model overrides")
    expect(!AppSettings.sanitizedImportedActions([]).isEmpty, "restores default actions when an import contains none")
}

func testDefaultPolishActionConfirmsReplacement() {
    let polish = AIAction.defaults().first { $0.name == "润色" }
    expect(polish?.replaceByDefault == true, "polish action enters replacement confirmation by default")
}

func testTextReplacementSelectionDelay() {
    expect(TextEditTransaction.selectionDelay(forCharacterCount: 0) == 0.03, "uses short delay for existing selections")
    expect(TextEditTransaction.selectionDelay(forCharacterCount: 100) > 0.03, "allows keyboard reselection to settle")
    expect(TextEditTransaction.selectionDelay(forCharacterCount: 10_000) == 0.75, "caps long reselection delay")
}

func testScreenCaptureTemporaryFileUsesUniqueUnpredictablePath() {
    let directory = URL(fileURLWithPath: "/tmp/snapai-test-temp", isDirectory: true)
    let firstUUID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    let secondUUID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    let first = ScreenCaptureTemporaryFile.makeURL(temporaryDirectory: directory,
                                                   uuid: firstUUID)
    let second = ScreenCaptureTemporaryFile.makeURL(temporaryDirectory: directory,
                                                    uuid: secondUUID)

    expect(first.deletingLastPathComponent().path == directory.path,
           "screen capture temporary files stay inside the supplied temporary directory")
    expect(first.pathExtension == "png",
           "screen capture temporary files use png extension for screencapture output")
    expect(first.lastPathComponent == "snapai-screen-\(firstUUID.uuidString).png",
           "screen capture temporary file names include an unpredictable UUID")
    expect(first != second,
           "screen capture temporary file names differ for different UUIDs")
    expect(!first.lastPathComponent.contains("snapai_ss_"),
           "screen capture temporary file names no longer use the old timestamp prefix")
}

func testScreenCapturePermissionPreflightAndRecoveryMessage() {
    expect(ScreenCapturePermission.isGranted(preflight: { true }),
           "screen capture permission helper reports granted preflight")
    expect(!ScreenCapturePermission.isGranted(preflight: { false }),
           "screen capture permission helper reports missing preflight")
    expect(ScreenCapturePermission.recoveryMessage.contains("屏幕录制"),
           "screen capture permission recovery message names the required permission")
    expect(ScreenCapturePermission.recoveryMessage.contains("允许 SnapAI"),
           "screen capture permission recovery message tells the user what to allow")
}

func testScreenCaptureFailureDiagnosticsAreShareableAndPathFree() {
    let diagnostic = ScreenCaptureFailureDiagnostic(
        reason: .commandFailed(1),
        permissionGranted: true,
        output: ScreenCaptureOutputSnapshot(exists: false, byteCount: nil)
    )

    expect(diagnostic.userMessage.contains("退出码 1"),
           "screen capture command failures explain the exit status")
    expect(diagnostic.userMessage.contains("屏幕录制"),
           "screen capture command failures include the recovery permission")
    expect(diagnostic.shareableText.contains("SnapAI Screen Capture Diagnostic"),
           "screen capture diagnostics identify their source")
    expect(diagnostic.shareableText.contains("Reason: command-failed"),
           "screen capture diagnostics include a stable reason code")
    expect(diagnostic.shareableText.contains("Command Exit Status: 1"),
           "screen capture diagnostics include the command exit status")
    expect(diagnostic.shareableText.contains("Output File Exists: no"),
           "screen capture diagnostics include output existence")
    expect(!diagnostic.shareableText.contains("/Users/"),
           "screen capture diagnostics avoid sharing local file paths")
}

func testScreenCaptureFailureDiagnosticsDescribeOutputProblems() {
    let emptyOutput = ScreenCaptureFailureDiagnostic(
        reason: .outputEmpty,
        permissionGranted: true,
        output: ScreenCaptureOutputSnapshot(exists: true, byteCount: 0)
    )
    let invalidImage = ScreenCaptureFailureDiagnostic(
        reason: .invalidImage,
        permissionGranted: true,
        output: ScreenCaptureOutputSnapshot(exists: true, byteCount: 128)
    )

    expect(emptyOutput.userMessage.contains("空图片文件"),
           "screen capture diagnostics explain empty output files")
    expect(emptyOutput.shareableText.contains("Output File Bytes: 0"),
           "screen capture diagnostics include empty output size")
    expect(invalidImage.userMessage.contains("无法解析"),
           "screen capture diagnostics explain invalid image output")
    expect(invalidImage.shareableText.contains("Output File Bytes: 128"),
           "screen capture diagnostics include invalid output size")
}

func testWriteBackUndoRecordAvailability() {
    let record = TextWriteBackRecord(targetApp: nil,
                                     originalText: "旧文本",
                                     replacementText: "新文本")
    expect(record.isUndoAvailable, "allows recent write-back undo")
    expect(record.undoState() == .available, "reports available undo state")
    expect(record.targetState == .missing, "reports missing target state for legacy records")
    expect(record.undoTitle == "撤销上次替换到 原应用", "uses generic replace title without target app")
    expect(record.diagnosticSummary.contains("undo=available"), "reports available undo in diagnostics")
    expect(record.diagnosticSummary.contains("targetState=missing"), "reports missing target state in diagnostics")
    expect(record.diagnosticSummary.contains("operation=replace"), "reports replace operation")
    expect(record.diagnosticSummary.contains("originalChars=3"), "reports original length")
    expect(record.diagnosticSummary.contains("replacementChars=3"), "reports replacement length")
    expect(record.recoverySuggestion == "可通过命令面板或菜单撤销上次写回",
           "available write-back records explain how to undo")
    expect(record.diagnosticSummary.contains("recovery=可通过命令面板或菜单撤销上次写回"),
           "write-back record diagnostics include recovery guidance")
    expect(!record.diagnosticSummary.contains("旧文本"), "does not leak original text")
    expect(!record.diagnosticSummary.contains("新文本"), "does not leak replacement text")

    let append = TextWriteBackRecord(targetApp: nil,
                                     operation: .append,
                                     originalText: "",
                                     replacementText: "\n追加内容")
    expect(append.isUndoAvailable, "allows recent append undo without original text")
    expect(append.undoTitle == "撤销上次追加到 原应用", "uses generic append title without target app")
    expect(append.diagnosticSummary.contains("operation=append"), "reports append operation")
    expect(!append.diagnosticSummary.contains("追加内容"), "does not leak appended text")

    let expired = TextWriteBackRecord(targetApp: nil,
                                      originalText: "旧文本",
                                      replacementText: "新文本",
                                      createdAt: Date(timeIntervalSinceNow: -TextWriteBackRecord.expirationInterval - 1))
    expect(!expired.isUndoAvailable, "expires stale write-back undo records")
    expect(expired.undoState() == .expired, "reports expired undo state")
    expect(expired.diagnosticSummary.contains("undo=expired"), "reports expired undo in diagnostics")
    expect(expired.recoverySuggestion == "撤销窗口已过期; 请在目标应用中手动恢复",
           "expired write-back records explain manual recovery")
    expect(expired.diagnosticSummary.contains("recovery=撤销窗口已过期; 请在目标应用中手动恢复"),
           "expired write-back diagnostics include recovery guidance")

    let empty = TextWriteBackRecord(targetApp: nil,
                                    originalText: "",
                                    replacementText: "新文本")
    expect(!empty.isUndoAvailable, "rejects empty undo records")
    expect(empty.undoState() == .missingOriginal, "reports missing original undo state")
    expect(empty.recoverySuggestion == "缺少原文快照; 请在目标应用中手动恢复",
           "missing-original write-back records explain manual recovery")

    let missingReplacement = TextWriteBackRecord(targetApp: nil,
                                                 originalText: "旧文本",
                                                 replacementText: "")
    expect(!missingReplacement.isUndoAvailable, "rejects missing replacement undo records")
    expect(missingReplacement.undoState() == .missingReplacement, "reports missing replacement undo state")
    expect(missingReplacement.recoverySuggestion == "缺少写回内容; 请重新复制结果或手动恢复",
           "missing-replacement write-back records explain recovery")

    expect(TextWriteBackRecord.resolvedTargetState(processIdentifier: nil,
                                                   isTerminated: false,
                                                   currentProcessIdentifier: 10) == .missing,
           "resolves missing write-back targets")
    expect(TextWriteBackRecord.resolvedTargetState(processIdentifier: 11,
                                                   isTerminated: true,
                                                   currentProcessIdentifier: 10) == .terminated,
           "resolves terminated write-back targets")
    expect(TextWriteBackRecord.resolvedTargetState(processIdentifier: 10,
                                                   isTerminated: false,
                                                   currentProcessIdentifier: 10) == .currentApp,
           "resolves current-app write-back targets")
    expect(TextWriteBackRecord.resolvedTargetState(processIdentifier: 11,
                                                   isTerminated: false,
                                                   currentProcessIdentifier: 10) == .running,
           "resolves running external write-back targets")
}

func testWriteBackFallbackDiagnosticSummarizesFailureWithoutContent() {
    expect(WriteBackCompatibility.profile(for: "Google Chrome")?.displayName == "浏览器",
           "writeback compatibility identifies browser targets")
    expect(WriteBackCompatibility.profile(for: "wechat")?.displayName == "微信",
           "writeback compatibility matches app aliases case-insensitively")
    expect(WriteBackCompatibility.recoveryHint(for: "Obsidian")?.contains("编辑模式") == true,
           "writeback compatibility provides app-specific recovery guidance")
    expect(WriteBackCompatibility.profile(for: "Unknown Notes") == nil,
           "writeback compatibility returns nil for unknown apps")

    let diagnostic = TextWriteBackFallbackDiagnostic(
        operation: .replace,
        targetApp: nil,
        reason: "目标不可用: /Users/alice/Documents/input.txt Authorization: Bearer sk-live-secret-value-1234567890",
        copiedToPasteboard: true,
        originalCharacterCount: 12,
        payloadCharacterCount: 34
    )
    let summary = diagnostic.diagnosticSummary

    expect(summary.contains("state=fallback-copied"),
           "writeback fallback diagnostics report fallback state")
    expect(summary.contains("operation=replace"),
           "writeback fallback diagnostics report operation")
    expect(summary.contains("targetState=missing"),
           "writeback fallback diagnostics report target state")
    expect(summary.contains("copiedToPasteboard=yes"),
           "writeback fallback diagnostics report pasteboard recovery")
    expect(summary.contains("originalChars=12"),
           "writeback fallback diagnostics report original length")
    expect(summary.contains("payloadChars=34"),
           "writeback fallback diagnostics report copied payload length")
    expect(summary.contains("recovery=回到原应用后手动粘贴剪贴板内容; 如需替换请重新选中原文"),
           "writeback fallback diagnostics include actionable recovery guidance")
    expect(diagnostic.recoverySuggestion == "回到原应用后手动粘贴剪贴板内容; 如需替换请重新选中原文",
           "writeback fallback recovery guidance matches missing replace targets")
    expect(diagnostic.noticeMessage.contains("建议: 回到原应用后手动粘贴剪贴板内容; 如需替换请重新选中原文"),
           "writeback fallback notice surfaces actionable recovery guidance")
    expect(diagnostic.noticeMessage.contains("结果已复制到剪贴板。"),
           "writeback fallback notice explains pasteboard recovery state")
    expect(!summary.contains("/Users/alice"),
           "writeback fallback diagnostics redact user paths")
    expect(summary.contains("/Users/[user]/Documents/input.txt"),
           "writeback fallback diagnostics keep useful redacted path suffix")
    expect(!summary.contains("sk-live-secret-value-1234567890"),
           "writeback fallback diagnostics redact secrets")
    expect(summary.contains("Authorization: Bearer [REDACTED]"),
           "writeback fallback diagnostics keep sanitized auth context")
    expect(!diagnostic.noticeMessage.contains("/Users/alice"),
           "writeback fallback notice redacts user paths")
    expect(!diagnostic.noticeMessage.contains("sk-live-secret-value-1234567890"),
           "writeback fallback notice redacts secrets")

    let append = TextWriteBackFallbackDiagnostic(
        operation: .append,
        targetApp: nil,
        reason: "paste failed",
        copiedToPasteboard: false,
        originalCharacterCount: 0,
        payloadCharacterCount: 20
    )
    expect(append.recoverySuggestion == "回到原应用后手动粘贴剪贴板内容; 如需追加请定位到目标位置; 若剪贴板未更新请手动复制结果",
           "writeback fallback recovery guidance adapts to append and pasteboard failure")
    expect(append.diagnosticSummary.contains("recovery=回到原应用后手动粘贴剪贴板内容; 如需追加请定位到目标位置; 若剪贴板未更新请手动复制结果"),
           "writeback fallback diagnostics include append recovery guidance")
    expect(append.noticeMessage.contains("结果未能自动复制到剪贴板。"),
           "writeback fallback notice explains pasteboard copy failure")
    expect(append.noticeMessage.contains("若剪贴板未更新请手动复制结果"),
           "writeback fallback notice explains manual copy recovery")

    let pasteboardSafetyRecovery = "当前剪贴板内容过大或格式过多,为避免丢失用户剪贴板,已取消自动粘贴。请手动复制结果后粘贴。"
    let protectedPasteboard = TextWriteBackFallbackDiagnostic(
        operation: .replace,
        targetApp: nil,
        reason: "pasteboard snapshot unsafe reason=too-large",
        copiedToPasteboard: false,
        originalCharacterCount: 12,
        payloadCharacterCount: 34,
        recoveryOverride: pasteboardSafetyRecovery
    )
    expect(protectedPasteboard.recoverySuggestion == pasteboardSafetyRecovery,
           "writeback fallback diagnostics can surface pasteboard safety recovery guidance")
    expect(protectedPasteboard.diagnosticSummary.contains("recovery=\(pasteboardSafetyRecovery)"),
           "writeback fallback summary keeps pasteboard safety recovery searchable")
    expect(protectedPasteboard.noticeMessage.contains("建议: \(pasteboardSafetyRecovery)"),
           "writeback fallback notice explains pasteboard safety cancellation")

    let chrome = TextWriteBackFallbackDiagnostic(
        operation: .replace,
        targetApp: nil,
        reason: "paste failed",
        copiedToPasteboard: true,
        originalCharacterCount: 12,
        payloadCharacterCount: 34,
        targetNameOverride: "Google Chrome"
    )
    expect(chrome.recoverySuggestion.contains("浏览器写回失败"),
           "writeback fallback diagnostics use browser-specific compatibility recovery")
    expect(chrome.diagnosticSummary.contains("浏览器写回失败"),
           "writeback fallback summary includes app-specific compatibility recovery")
}

func testWriteBackUndoFallbackDiagnosticSummarizesFailureWithoutContent() {
    let record = TextWriteBackRecord(targetApp: nil,
                                     operation: .replace,
                                     originalText: "替换前的敏感原文",
                                     replacementText: "替换后的敏感结果")
    let diagnostic = TextWriteBackUndoFallbackDiagnostic(
        record: record,
        reason: "目标不可用: /Users/alice/Documents/input.txt Authorization: Bearer sk-live-secret-value-1234567890",
        copiedOriginalToPasteboard: true
    )
    let summary = diagnostic.diagnosticSummary

    expect(summary.contains("state=undo-fallback"),
           "writeback undo fallback diagnostics report undo fallback state")
    expect(summary.contains("undo=available"),
           "writeback undo fallback diagnostics keep the original undo state")
    expect(summary.contains("operation=replace"),
           "writeback undo fallback diagnostics report operation")
    expect(summary.contains("targetState=missing"),
           "writeback undo fallback diagnostics report target state")
    expect(summary.contains("copiedOriginalToPasteboard=yes"),
           "writeback undo fallback diagnostics report copied original recovery")
    expect(summary.contains("originalChars=8"),
           "writeback undo fallback diagnostics report original length")
    expect(summary.contains("replacementChars=8"),
           "writeback undo fallback diagnostics report replacement length")
    expect(summary.contains("recovery=替换前的原文已复制到剪贴板; 请回到目标应用手动粘贴恢复"),
           "writeback undo fallback diagnostics include recovery guidance")
    expect(diagnostic.noticeMessage.contains("建议: 替换前的原文已复制到剪贴板; 请回到目标应用手动粘贴恢复"),
           "writeback undo fallback notice surfaces recovery guidance")
    expect(!summary.contains("替换前的敏感原文") && !summary.contains("替换后的敏感结果"),
           "writeback undo fallback diagnostics do not include document content")
    expect(!diagnostic.noticeMessage.contains("替换前的敏感原文") && !diagnostic.noticeMessage.contains("替换后的敏感结果"),
           "writeback undo fallback notice does not include document content")
    expect(!summary.contains("/Users/alice") && !diagnostic.noticeMessage.contains("/Users/alice"),
           "writeback undo fallback messages redact user paths")
    expect(!summary.contains("sk-live-secret-value-1234567890") && !diagnostic.noticeMessage.contains("sk-live-secret-value-1234567890"),
           "writeback undo fallback messages redact secrets")

    let append = TextWriteBackUndoFallbackDiagnostic(
        record: TextWriteBackRecord(targetApp: nil,
                                    operation: .append,
                                    originalText: "",
                                    replacementText: "追加内容"),
        reason: "原应用暂不可用",
        copiedOriginalToPasteboard: false
    )
    expect(append.recoverySuggestion == "请在目标应用中使用系统撤销,或手动移除上次追加内容",
           "writeback undo fallback adapts recovery for append operations")
    expect(append.diagnosticSummary.contains("copiedOriginalToPasteboard=no"),
           "writeback undo fallback reports when no original was copied")

    let pasteboardUndoRecovery = "当前剪贴板内容过大或格式过多,为避免丢失用户剪贴板,已取消自动撤销。请在目标应用中使用系统撤销,或手动恢复。"
    let protectedPasteboardUndo = TextWriteBackUndoFallbackDiagnostic(
        record: record,
        reason: "pasteboard snapshot unsafe reason=too-large",
        copiedOriginalToPasteboard: false,
        recoveryOverride: pasteboardUndoRecovery
    )
    expect(protectedPasteboardUndo.recoverySuggestion == pasteboardUndoRecovery,
           "writeback undo fallback diagnostics can surface pasteboard safety recovery guidance")
    expect(protectedPasteboardUndo.diagnosticSummary.contains("recovery=\(pasteboardUndoRecovery)"),
           "writeback undo fallback summary keeps pasteboard safety recovery searchable")
    expect(protectedPasteboardUndo.noticeMessage.contains("建议: \(pasteboardUndoRecovery)"),
           "writeback undo fallback notice explains pasteboard safety cancellation")
}

func testWriteBackCommandFactoryReflectsUndoAvailability() {
    expect(WriteBackCommandFactory.undoDescriptor(for: nil) == nil,
           "missing writeback record produces no undo command")
    expect(WriteBackCommandFactory.undoMenuTitle(for: nil) == "撤销上次写回",
           "missing writeback record uses generic menu title")

    let replace = TextWriteBackRecord(targetApp: nil,
                                      operation: .replace,
                                      originalText: "旧文本",
                                      replacementText: "新文本")
    let replaceDescriptor = WriteBackCommandFactory.undoDescriptor(for: replace)
    expect(replaceDescriptor?.id == "undo-write-back", "writeback undo command uses stable id")
    expect(replaceDescriptor?.title == "撤销上次替换到 原应用", "replace undo command uses record title")
    expect(replaceDescriptor?.subtitle == "恢复替换前的原文", "replace undo command explains restore behavior")
    expect(replaceDescriptor?.keywords.contains("替换") == true, "replace undo command is searchable by replace")
    expect(replaceDescriptor?.shortcutText == WriteBackCommandFactory.undoShortcutText,
           "writeback undo command exposes its menu shortcut")
    expect(replaceDescriptor?.action == .undoLastWriteBack, "writeback undo command carries undo action")
    expect(WriteBackCommandFactory.undoMenuTitle(for: replace) == replace.undoTitle,
           "available writeback record drives menu title")
    expect(WriteBackCommandFactory.statusSummary(for: replace,
                                                 fallback: "state=fallback-copied")?.contains("operation=replace") == true,
           "writeback status summary prefers live records over stale fallback strings")

    let append = TextWriteBackRecord(targetApp: nil,
                                     operation: .append,
                                     originalText: "",
                                     replacementText: "\n追加")
    let appendDescriptor = WriteBackCommandFactory.undoDescriptor(for: append)
    expect(appendDescriptor?.subtitle == "移除上次追加内容", "append undo command explains removal behavior")
    expect(appendDescriptor?.keywords.contains("追加") == true, "append undo command is searchable by append")

    let expired = TextWriteBackRecord(targetApp: nil,
                                      originalText: "旧文本",
                                      replacementText: "新文本",
                                      createdAt: Date(timeIntervalSinceNow: -TextWriteBackRecord.expirationInterval - 1))
    expect(WriteBackCommandFactory.undoDescriptor(for: expired) == nil,
           "expired writeback record produces no undo command")
    let expiredStatus = WriteBackCommandFactory.statusSummary(for: expired,
                                                              fallback: "state=available")
    expect(expiredStatus?.contains("state=unavailable") == true &&
           expiredStatus?.contains("undo=expired") == true,
           "writeback status summary reports live expiration instead of stale availability")
    expect(WriteBackCommandFactory.statusSummary(for: nil,
                                                 fallback: "state=fallback-copied") == "state=fallback-copied",
           "writeback status summary falls back when no live record exists")
}

func testCapturedTextPreservesSelectionWhitespace() {
    expect(TextCapture.usableCapturedText("  hello\n") == "  hello\n", "preserves selected whitespace for exact replacement")
    expect(TextCapture.usableCapturedText(" \n\t") == nil, "rejects whitespace-only captures")
}

func testTextCaptureRecoveryGuidePointsToActionablePermissionHelp() {
    expect(TextCaptureRecoveryGuide.title == "未检测到选中的文字",
           "text capture recovery guide uses the no-selection alert title")
    expect(TextCaptureRecoveryGuide.message.contains("权限健康中心"),
           "text capture recovery guide points to permission health")
    expect(TextCaptureRecoveryGuide.message.contains("快捷提问"),
           "text capture recovery guide offers quick input fallback")
    expect(TextCaptureRecoveryGuide.message.contains("辅助功能权限"),
           "text capture recovery guide names accessibility permission")
    expect(TextCaptureRecoveryGuide.message.contains("剪贴板复制兜底"),
           "text capture recovery guide mentions copy fallback")
    expect(TextCaptureRecoveryGuide.quickInputButtonTitle == "打开快捷提问",
           "text capture recovery guide exposes quick input button title")
    expect(TextCaptureRecoveryGuide.permissionHealthButtonTitle == "打开权限健康中心",
           "text capture recovery guide exposes permission health button title")
    expect(TextCaptureRecoveryGuide.accessibilitySettingsButtonTitle == "打开辅助功能设置",
           "text capture recovery guide exposes accessibility settings button title")
    expect(TextCaptureRecoveryGuide.accessibilitySettingsURL.absoluteString.contains("Privacy_Accessibility"),
           "text capture recovery guide opens the accessibility privacy pane")
}

func testTextCaptureDiagnosticSummarizesStateWithoutContent() {
    let captured = TextCaptureDiagnostic.captured(accessibilityGranted: true,
                                                  preferAX: true,
                                                  frontmostAppName: "Pages",
                                                  characterCount: 42)
    expect(captured.diagnosticSummary.contains("state=captured"),
           "text capture diagnostics report captured state")
    expect(captured.diagnosticSummary.contains("accessibility=granted"),
           "text capture diagnostics report accessibility state")
    expect(captured.diagnosticSummary.contains("preferAX=yes"),
           "text capture diagnostics report capture preference")
    expect(captured.diagnosticSummary.contains("frontmostApp=Pages"),
           "text capture diagnostics report sanitized frontmost app name")
    expect(captured.diagnosticSummary.contains("capturedChars=42"),
           "text capture diagnostics report character count")
    expect(captured.recoverySuggestion == "无需处理",
           "successful text capture diagnostics need no recovery")
    expect(captured.diagnosticSummary.contains("recovery=无需处理"),
           "text capture diagnostics include recovery guidance")

    let failed = TextCaptureDiagnostic.noSelection(accessibilityGranted: false,
                                                   preferAX: true,
                                                   frontmostAppName: "Secret sk-live-secret-value-1234567890")
    expect(failed.diagnosticSummary.contains("state=no-selection"),
           "text capture diagnostics report no-selection state")
    expect(failed.diagnosticSummary.contains("accessibility=missing"),
           "text capture diagnostics report missing accessibility")
    expect(failed.diagnosticSummary.contains("capturedChars=0"),
           "text capture diagnostics do not include selected text content")
    expect(failed.recoverySuggestion == "授予辅助功能权限后重试; 也可打开快捷提问",
           "text capture diagnostics explain missing accessibility recovery")
    expect(failed.diagnosticSummary.contains("recovery=授予辅助功能权限后重试; 也可打开快捷提问"),
           "failed text capture diagnostics include recovery guidance")
    expect(!failed.diagnosticSummary.contains("sk-live-secret-value-1234567890"),
           "text capture diagnostics redact sensitive app metadata")

    let axNoSelection = TextCaptureDiagnostic.noSelection(accessibilityGranted: true,
                                                          preferAX: true,
                                                          frontmostAppName: "Pages")
    expect(axNoSelection.recoverySuggestion == "重新选中文字后重试; 若目标应用不兼容,可打开快捷提问",
           "AX text capture diagnostics explain incompatible target recovery")

    let copyFallbackNoSelection = TextCaptureDiagnostic.noSelection(accessibilityGranted: true,
                                                                    preferAX: false,
                                                                    frontmostAppName: "Pages")
    expect(copyFallbackNoSelection.recoverySuggestion == "重新选中文字后重试; 确认目标应用允许复制,也可打开快捷提问",
           "clipboard fallback text capture diagnostics explain copy recovery")
}

func testSystemPrivacySettingsBuildsStablePaneURLs() {
    expect(SystemPrivacySettings.accessibilityURL.absoluteString == "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
           "system privacy settings opens accessibility pane")
    expect(SystemPrivacySettings.screenCaptureURL.absoluteString == "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
           "system privacy settings opens screen recording pane")
    expect(SystemPrivacySettings.url(for: .accessibility) == SystemPrivacySettings.accessibilityURL,
           "system privacy settings reuses accessibility helper")
    expect(SystemPrivacySettings.url(for: .screenCapture) == SystemPrivacySettings.screenCaptureURL,
           "system privacy settings reuses screen recording helper")
}

func testPasteboardRestoreDecisionProtectsUserChanges() {
    expect(TextCapture.shouldRestorePasteboard(expectedChangeCount: 42,
                                               currentChangeCount: 42),
           "restores the previous pasteboard when SnapAI's injected pasteboard item is still current")
    expect(!TextCapture.shouldRestorePasteboard(expectedChangeCount: 42,
                                                currentChangeCount: 43),
           "does not restore when the pasteboard changed after SnapAI injected text")

    let limits = PasteboardSnapshotLimits(maxItemCount: 2,
                                          maxTypeCount: 3,
                                          maxTotalByteCount: 10)
    expect(TextCapture.pasteboardSnapshotRejectionReason(itemCount: 2,
                                                         typeCount: 3,
                                                         totalByteCount: 10,
                                                         limits: limits) == nil,
           "allows pasteboard snapshots at the configured safety boundary")
    expect(TextCapture.pasteboardSnapshotRejectionReason(itemCount: 3,
                                                         typeCount: 1,
                                                         totalByteCount: 1,
                                                         limits: limits) == "too-many-items",
           "rejects pasteboard snapshots with too many items")
    expect(TextCapture.pasteboardSnapshotRejectionReason(itemCount: 1,
                                                         typeCount: 4,
                                                         totalByteCount: 1,
                                                         limits: limits) == "too-many-types",
           "rejects pasteboard snapshots with too many data types")
    expect(TextCapture.pasteboardSnapshotRejectionReason(itemCount: 1,
                                                         typeCount: 1,
                                                         totalByteCount: 11,
                                                         limits: limits) == "too-large",
           "rejects pasteboard snapshots that exceed the byte budget")

    let incomplete = PasteboardSnapshot.incomplete(reasonCode: "too-large",
                                                   totalByteCount: 11,
                                                   itemCount: 1,
                                                   typeCount: 1)
    expect(!incomplete.canRestore,
           "incomplete pasteboard snapshots are not considered safe to restore")
    expect(incomplete.recoveryMessage.contains("已取消自动粘贴"),
           "incomplete pasteboard snapshots explain that automatic paste was cancelled")
    expect(incomplete.undoRecoveryMessage.contains("已取消自动撤销"),
           "incomplete pasteboard snapshots explain that automatic undo was cancelled")
}

func testTextCaptureValidatesAXCoreFoundationTypes() {
    let element = AXUIElementCreateSystemWide()
    expect(TextCapture.isAXUIElementRef(element), "accepts AXUIElement Core Foundation values")
    expect(!TextCapture.isAXValueRef(element), "does not confuse AXUIElement with AXValue")

    var range = CFRange(location: 1, length: 2)
    guard let axValue = AXValueCreate(.cfRange, &range) else {
        expect(false, "creates AXValue range fixture")
        return
    }
    expect(TextCapture.isAXValueRef(axValue), "accepts AXValue Core Foundation values")
    expect(!TextCapture.isAXUIElementRef(axValue), "does not confuse AXValue with AXUIElement")
}

func testHotKeyConflictDetection() {
    var ask = AIAction.defaults()[0]
    ask.id = "ask"
    var translate = AIAction.defaults()[1]
    translate.id = "translate"
    let conflict = HotKeyConflictDetector.conflict(
        for: ask.hotKey!,
        actions: [ask, translate],
        excludingActionID: "translate",
        quickPanelHotKey: .quickPanelDefault,
        includeQuickPanel: true
    )
    expect(conflict != nil, "detects action hotkey conflict")
    expect(HotKeyConflictDetector.systemWarning(
        for: HotKeyCombo(keyCode: UInt32(kVK_ANSI_Q), modifiers: UInt32(cmdKey))
    ) != nil, "warns for common system shortcut")
}

func testCommandPaletteMatchesMultipleTerms() {
    expect(CommandPaletteMatcher.matches(title: "复制完整结果",
                                         subtitle: "Markdown,含原文、结果、模型和路由摘要",
                                         keywords: "result markdown export copy 完整 结果",
                                         query: "copy result"),
           "matches multiple terms across keywords")
    expect(CommandPaletteMatcher.matches(title: "复制完整结果",
                                         subtitle: "Markdown,含原文、结果、模型和路由摘要",
                                         keywords: "result markdown export copy 完整 结果",
                                         query: "完整 markdown"),
           "matches mixed title and keyword terms")
    expect(!CommandPaletteMatcher.matches(title: "复制完整结果",
                                          subtitle: "Markdown,含原文、结果、模型和路由摘要",
                                          keywords: "result markdown export copy 完整 结果",
                                          query: "history delete"),
           "rejects unrelated multi-term query")
    expect(CommandPaletteMatcher.matches(title: "gpt-4o-mini",
                                         subtitle: "切换模型 - Open AI",
                                         keywords: "model provider",
                                         query: "gpt4o"),
           "matches compact model queries without separators")
    expect(CommandPaletteMatcher.matches(title: "切换模型",
                                         subtitle: "Open AI / gpt-4o-mini",
                                         keywords: "provider",
                                         query: "openai"),
           "matches compact provider queries without spaces")
    expect(CommandPaletteMatcher.matches(title: "复制标签「项目A」历史",
                                         subtitle: "2 条记录,Markdown",
                                         keywords: "history export copy tag 项目A",
                                         query: "标签：项目A"),
           "matches queries separated by full-width colon")
    expect(CommandPaletteMatcher.matches(title: "复制全部历史",
                                         subtitle: "Markdown,含原文、结果、模型",
                                         keywords: "history export copy markdown 历史 导出 复制",
                                         query: "复制，历史"),
           "matches queries separated by Chinese comma")
    expect(CommandPaletteMatcher.matches(title: "复制模型「gpt-4o-mini」历史",
                                         subtitle: "2 条记录,Markdown",
                                         keywords: "history export copy model gpt-4o-mini",
                                         query: "模型《gpt4o》"),
           "matches compact terms wrapped in Chinese punctuation")
}

func testCommandPaletteRanksMatchesByRelevance() {
    struct Fixture {
        let id: String
        let title: String
        let subtitle: String
        let keywords: String
    }
    let items = [
        Fixture(id: "keyword", title: "打开设置", subtitle: "供应商、动作、隐私", keywords: "model provider settings"),
        Fixture(id: "title", title: "模型设置", subtitle: "供应商和路由", keywords: "settings"),
        Fixture(id: "subtitle", title: "检查更新", subtitle: "模型 manifest", keywords: "release")
    ]
    let ranked = CommandPaletteMatcher.ranked(items, query: "模型") { item in
        (title: item.title, subtitle: item.subtitle, keywords: item.keywords)
    }
    expect(ranked.map(\.id) == ["title", "subtitle"], "ranks title matches before subtitle matches and filters keyword-only misses")

    let stable = CommandPaletteMatcher.ranked(items, query: "") { item in
        (title: item.title, subtitle: item.subtitle, keywords: item.keywords)
    }
    expect(stable.map(\.id) == ["keyword", "title", "subtitle"], "preserves original order for empty query")

    let compactRanked = CommandPaletteMatcher.ranked([
        Fixture(id: "compact", title: "gpt-4o-mini", subtitle: "切换模型", keywords: ""),
        Fixture(id: "prefix", title: "gpt4o local", subtitle: "切换模型", keywords: "")
    ], query: "gpt4o") { item in
        (title: item.title, subtitle: item.subtitle, keywords: item.keywords)
    }
    expect(compactRanked.map(\.id) == ["prefix", "compact"],
           "ranks direct prefix matches before compact separator-insensitive matches")
}

func testCommandPaletteSearchesShortcutTextAliases() {
    let keywords = CommandPaletteMatcher.shortcutSearchKeywords("⌘⇧C")
    let keywordParts = keywords.split(separator: " ").map(String.init)
    expect(Array(keywordParts.prefix(5)) == ["⌘⇧c", "cmd", "command", "shift", "c"],
           "shortcut keywords preserve first occurrence order")
    expect(Set(keywordParts).count == keywordParts.count,
           "shortcut keywords remove duplicates without reordering")
    expect(keywords.contains("cmd"), "shortcut keywords include cmd alias")
    expect(keywords.contains("command"), "shortcut keywords include command alias")
    expect(keywords.contains("shift"), "shortcut keywords include shift alias")
    expect(keywords.contains("c"), "shortcut keywords include key")
    let spaceKeywords = CommandPaletteMatcher.shortcutSearchKeywords("⌥Space")
    expect(spaceKeywords.contains("space"), "shortcut keywords include Space text key")
    expect(spaceKeywords.contains("optionspace"), "shortcut keywords include compact option-space alias")
    let symbolSpaceKeywords = CommandPaletteMatcher.shortcutSearchKeywords("⌘␣")
    expect(symbolSpaceKeywords.contains("cmdspace"), "shortcut keywords include compact command-space alias")
    let escapeKeywords = CommandPaletteMatcher.shortcutSearchKeywords("⌘⎋")
    expect(escapeKeywords.contains("cmdesc"), "shortcut keywords include compact command-escape alias")
    expect(escapeKeywords.contains("escape"), "shortcut keywords include escape alias for symbol key")
    let returnKeywords = CommandPaletteMatcher.shortcutSearchKeywords("⌘⇧↩")
    expect(returnKeywords.contains("return"), "shortcut keywords include return alias for return symbol")
    expect(returnKeywords.contains("enter"), "shortcut keywords include enter alias for return symbol")
    expect(returnKeywords.contains("cmdshiftreturn"), "shortcut keywords include compact command-shift-return alias")
    expect(returnKeywords.contains("cmdshiftenter"), "shortcut keywords include compact command-shift-enter alias")
    let optionKeywords = CommandPaletteMatcher.shortcutSearchKeywords("⌘⌥C")
    expect(optionKeywords.contains("cmdoptionc"), "shortcut keywords include primary command-option compact alias")
    expect(optionKeywords.contains("cmdoptc"), "shortcut keywords include short option compact alias")
    expect(optionKeywords.contains("cmdaltc"), "shortcut keywords include alt compact alias")
    expect(optionKeywords.contains("commandaltc"), "shortcut keywords include command-alt compact alias")
    let forwardDeleteKeywords = CommandPaletteMatcher.shortcutSearchKeywords("⌘⌦")
    expect(forwardDeleteKeywords.contains("forwarddelete"), "shortcut keywords include forward delete alias")
    expect(forwardDeleteKeywords.contains("cmdforwarddelete"), "shortcut keywords include compact command-forward-delete alias")
    expect(forwardDeleteKeywords.contains("cmddelete"), "shortcut keywords include compact command-delete alias")
    let deleteKeywords = CommandPaletteMatcher.shortcutSearchKeywords("Delete")
    expect(deleteKeywords.contains("delete"), "shortcut keywords include Delete text key")
    let backspaceKeywords = CommandPaletteMatcher.shortcutSearchKeywords("Backspace")
    expect(backspaceKeywords.contains("backspace"), "shortcut keywords include Backspace text key")
    expect(backspaceKeywords.contains("delete"), "shortcut keywords treat Backspace as a delete key")
    expect(!backspaceKeywords.split(separator: " ").contains("space"),
           "shortcut keywords do not treat Backspace as Space")

    expect(CommandPaletteMatcher.matches(title: "复制结果",
                                         subtitle: "当前结果面板",
                                         keywords: "result copy \(CommandPaletteMatcher.shortcutSearchKeywords("⌘⇧C"))",
                                         query: "cmd shift c"),
           "command palette matcher matches shortcut aliases")
    expect(CommandPaletteMatcher.matches(title: "复制结果",
                                         subtitle: "当前结果面板",
                                         keywords: "result copy \(CommandPaletteMatcher.shortcutSearchKeywords("⌘⇧C"))",
                                         query: "command c"),
           "command palette matcher matches command alias and key")
    expect(CommandPaletteMatcher.matches(title: "复制结果",
                                         subtitle: "当前结果面板",
                                         keywords: "result copy \(CommandPaletteMatcher.shortcutSearchKeywords("⌘⇧C"))",
                                         query: "cmd+shift+c"),
           "command palette matcher treats plus signs as shortcut separators")
    expect(CommandPaletteMatcher.matches(title: "复制结果",
                                         subtitle: "当前结果面板",
                                         keywords: "result copy \(CommandPaletteMatcher.shortcutSearchKeywords("⌘⇧C"))",
                                         query: "⌘+⇧+C"),
           "command palette matcher handles symbol shortcuts with separators")
    expect(CommandPaletteMatcher.matches(title: "快捷提问",
                                         subtitle: "打开快捷提问面板",
                                         keywords: "quick ask \(CommandPaletteMatcher.shortcutSearchKeywords("⌥Space"))",
                                         query: "option space"),
           "command palette matcher matches option-space shortcut")
    expect(CommandPaletteMatcher.matches(title: "快捷提问",
                                         subtitle: "打开快捷提问面板",
                                         keywords: "quick ask \(CommandPaletteMatcher.shortcutSearchKeywords("⌥Space"))",
                                         query: "optionspace"),
           "command palette matcher matches compact option-space shortcut")
    expect(CommandPaletteMatcher.matches(title: "停止生成",
                                         subtitle: "当前结果面板",
                                         keywords: "result stop \(CommandPaletteMatcher.shortcutSearchKeywords("Esc"))",
                                         query: "escape"),
           "command palette matcher matches escape alias for Esc text")
    expect(CommandPaletteMatcher.matches(title: "追加到文档",
                                         subtitle: "当前结果面板",
                                         keywords: "result append \(CommandPaletteMatcher.shortcutSearchKeywords("⌘⇧↩"))",
                                         query: "cmdshiftenter"),
           "command palette matcher matches compact command-shift-enter shortcut")
    expect(CommandPaletteMatcher.matches(title: "追加到文档",
                                         subtitle: "当前结果面板",
                                         keywords: "result append \(CommandPaletteMatcher.shortcutSearchKeywords("⌘⇧↩"))",
                                         query: "cmd return"),
           "command palette matcher matches command-return alias")
    expect(CommandPaletteMatcher.matches(title: "复制完整结果",
                                         subtitle: "当前结果面板",
                                         keywords: "result copy markdown \(CommandPaletteMatcher.shortcutSearchKeywords("⌘⌥C"))",
                                         query: "cmdoptc"),
           "command palette matcher matches compact command-option shortcut with opt alias")
    expect(CommandPaletteMatcher.matches(title: "复制完整结果",
                                         subtitle: "当前结果面板",
                                         keywords: "result copy markdown \(CommandPaletteMatcher.shortcutSearchKeywords("⌘⌥C"))",
                                         query: "cmdaltc"),
           "command palette matcher matches compact command-option shortcut with alt alias")
    expect(CommandPaletteMatcher.matches(title: "删除历史",
                                         subtitle: "历史记录",
                                         keywords: "history delete \(CommandPaletteMatcher.shortcutSearchKeywords("⌘⌦"))",
                                         query: "cmddelete"),
           "command palette matcher matches compact command-delete shortcut")
    expect(CommandPaletteMatcher.matches(title: "gpt-4o-mini",
                                         subtitle: "当前模型 - OpenAI",
                                         keywords: "model provider ai switch",
                                         query: "gpt-4o"),
           "command palette matcher splits hyphenated model queries without losing matches")

    struct Fixture {
        let id: String
        let title: String
        let subtitle: String
        let keywords: String
    }
    let ranked = CommandPaletteMatcher.ranked([
        Fixture(id: "quick",
                title: "快捷提问",
                subtitle: "打开快捷提问面板",
                keywords: "quick ask \(CommandPaletteMatcher.shortcutSearchKeywords("⌥Space"))"),
        Fixture(id: "copy",
                title: "复制结果",
                subtitle: "当前结果面板",
                keywords: "result copy \(CommandPaletteMatcher.shortcutSearchKeywords("⌘⇧C"))")
    ], query: "cmd shift c") { item in
        (title: item.title, subtitle: item.subtitle, keywords: item.keywords)
    }
    expect(ranked.map(\.id) == ["copy"], "command palette ranking indexes shortcut aliases")

    let unsafeSearchKeywords = MarkdownExportSafety.keywords([
        "alpha\napi_key=supersecret123456|`mark`",
        CommandPaletteMatcher.shortcutSearchKeywords("⌘⇧K")
    ])
    expect(unsafeSearchKeywords.contains("alpha"), "command palette keeps safe keyword content")
    expect(unsafeSearchKeywords.contains("cmdshiftk"), "command palette still indexes shortcut aliases")
    expect(!unsafeSearchKeywords.contains("supersecret123456"),
           "command palette searchable keywords redact key-like fragments")
    expect(!unsafeSearchKeywords.contains("\n") &&
           !unsafeSearchKeywords.contains("|") &&
           !unsafeSearchKeywords.contains("`"),
           "command palette searchable keywords are single-line and markdown-safe")
}

func testCommandIdentifierSlugAndUniqueness() {
    expect(CommandIdentifier.slug(for: " gpt/4o mini ") == "gpt-4o-mini",
           "command identifier slug replaces separators and trims edges")
    expect(CommandIdentifier.slug(for: "项目/Alpha") == "项目-Alpha",
           "command identifier slug keeps readable unicode letters")
    expect(CommandIdentifier.slug(for: " / ") == "untitled",
           "command identifier slug falls back for separator-only values")

    var usedIDs: Set<String> = ["model-local-gpt-4o-mini"]
    let first = CommandIdentifier.unique(prefix: "model",
                                         values: ["local", "gpt/4o mini"],
                                         usedIDs: &usedIDs)
    let second = CommandIdentifier.unique(prefix: "model",
                                          values: ["local", "gpt 4o mini"],
                                          usedIDs: &usedIDs)
    expect(first == "model-local-gpt-4o-mini-2",
           "command identifier unique appends suffix for existing ids")
    expect(second == "model-local-gpt-4o-mini-3",
           "command identifier unique keeps suffixing for repeated collisions")

    var baseIDs: Set<String> = ["settings"]
    let duplicateBase = CommandIdentifier.unique(base: "settings", usedIDs: &baseIDs)
    let rawBase = CommandIdentifier.unique(base: "team/A", usedIDs: &baseIDs)
    expect(duplicateBase == "settings-2",
           "command identifier unique base appends suffix for duplicate item ids")
    expect(rawBase == "team-A",
           "command identifier unique base slugs raw item ids before use")

    expect(CommandIdentifier.uniqued(["settings", "settings", "team/A", " / "]) == [
        "settings",
        "settings-2",
        "team-A",
        "untitled"
    ], "command identifier uniqued maps item id lists to stable safe unique ids")
}

func testModelSwitchCommandFactoryFiltersAndMarksCurrentModel() {
    var primary = AIProvider(name: "OpenAI",
                             apiProtocol: .openAI,
                             baseURL: "https://api.openai.com/v1",
                             apiKey: "key",
                             models: [
                                AIModelEntry(name: "gpt-4o-mini"),
                                AIModelEntry(name: "disabled-model", enabled: false)
                             ])
    primary.id = "openai"
    primary.isEnabled = true
    var disabledProvider = AIProvider(name: "Disabled",
                                      apiProtocol: .openAI,
                                      baseURL: "https://disabled.test/v1",
                                      apiKey: "key",
                                      models: [AIModelEntry(name: "hidden-model")])
    disabledProvider.id = "disabled"
    disabledProvider.isEnabled = false
    var fallback = AIProvider(name: "DeepSeek",
                              apiProtocol: .openAI,
                              baseURL: "https://api.deepseek.com/v1",
                              apiKey: "key",
                              models: [AIModelEntry(name: "deepseek-chat")])
    fallback.id = "deepseek"
    fallback.isEnabled = true

    let descriptors = ModelSwitchCommandFactory.descriptors(providers: [primary, disabledProvider, fallback],
                                                            activeProviderID: "openai",
                                                            activeModel: "gpt-4o-mini")

    expect(descriptors.map(\.id) == [
        "model-openai-gpt-4o-mini",
        "model-deepseek-deepseek-chat"
    ], "model switch commands include enabled provider models only")
    expect(descriptors[0].subtitle == "当前模型 - OpenAI", "current model is marked in subtitle")
    expect(descriptors[0].systemImage == "checkmark.circle.fill", "current model uses check icon")
    expect(descriptors[1].subtitle == "切换模型 - DeepSeek", "non-current model offers switch")
    expect(descriptors[1].keywords.contains("deepseek-chat"), "model command is searchable by model")
    expect(descriptors[1].providerID == "deepseek" && descriptors[1].modelName == "deepseek-chat",
           "model command carries switch target")
}

func testModelSwitchCommandIDsAreStableSlugs() {
    var provider = AIProvider(name: "Local",
                              apiProtocol: .openAI,
                              baseURL: "http://localhost:11434/v1",
                              apiKey: "key",
                              models: [
                                AIModelEntry(name: "gpt/4o mini"),
                                AIModelEntry(name: "gpt 4o mini")
                              ])
    provider.id = "local/test"
    provider.isEnabled = true

    let descriptors = ModelSwitchCommandFactory.descriptors(providers: [provider],
                                                            activeProviderID: "local/test",
                                                            activeModel: "gpt/4o mini")

    expect(descriptors.map(\.id) == [
        "model-local-test-gpt-4o-mini",
        "model-local-test-gpt-4o-mini-2"
    ], "model switch command ids slug provider and model values with collision suffixes")
    expect(descriptors.map(\.modelName) == ["gpt/4o mini", "gpt 4o mini"],
           "model switch command ids do not alter switch target model names")
    expect(descriptors.allSatisfy { !$0.id.contains("/") && !$0.id.contains(" ") },
           "model switch command ids do not contain path or whitespace separators")

    var unsafeProvider = AIProvider(name: "Local\nLab|`A`",
                                    apiProtocol: .openAI,
                                    baseURL: "http://localhost:11434/v1",
                                    apiKey: "key",
                                    models: [AIModelEntry(name: "gpt\n4o|mini")])
    unsafeProvider.id = "unsafe"
    unsafeProvider.isEnabled = true
    let unsafe = ModelSwitchCommandFactory.descriptors(providers: [unsafeProvider],
                                                       activeProviderID: "unsafe",
                                                       activeModel: "gpt\n4o|mini")
    expect(unsafe.first?.title == "gpt 4o/mini", "model command title keeps unsafe model names single-line")
    expect(unsafe.first?.subtitle == "当前模型 - Local Lab/'A'",
           "model command subtitle keeps unsafe provider names single-line")
    expect(unsafe.first?.modelName == "gpt\n4o|mini",
           "model command action target keeps the original model name")
    expect(unsafe.first?.keywords.contains("\n") == false &&
           unsafe.first?.keywords.contains("|") == false &&
           unsafe.first?.keywords.contains("`") == false,
           "model command keywords keep unsafe provider and model names search-safe")
}

func testActionCommandFactoryFiltersAndFormatsActions() {
    var enabled = AIAction(name: "代码审查",
                           icon: "",
                           group: "开发",
                           hotKey: HotKeyCombo(keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(optionKey)))
    enabled.id = "review"
    enabled.isEnabled = true
    var disabled = AIAction(name: "禁用动作",
                            icon: "xmark",
                            group: "隐藏")
    disabled.id = "disabled"
    disabled.isEnabled = false
    var plain = AIAction(name: "无快捷键",
                         icon: "sparkles",
                         group: "")
    plain.id = "plain"
    plain.isEnabled = true

    let descriptors = ActionCommandFactory.descriptors(for: [enabled, disabled, plain]) { action in
        action.hotKey?.displayString
    }

    expect(descriptors.map(\.id) == ["action-review", "action-plain"],
           "action commands include enabled actions only")
    expect(descriptors[0].title == "代码审查", "action command uses action name")
    expect(descriptors[0].subtitle == "动作 - 开发", "action command shows action group in subtitle")
    expect(descriptors[0].shortcutText == "⌥R", "action command exposes hotkey separately")
    expect(descriptors[0].systemImage == "wand.and.stars", "action command falls back when icon is blank")
    expect(descriptors[0].keywords.contains("开发"), "action command is searchable by group")
    expect(descriptors[0].actionID == "review", "action command carries action target")
    expect(descriptors[1].subtitle == "动作", "action command falls back when hotkey is absent")
    expect(descriptors[1].shortcutText == nil, "action command omits shortcut text when hotkey is absent")
    expect(descriptors[1].systemImage == "sparkles", "action command preserves configured icon")

    var unsafe = AIAction(name: "润色\n# 注入|`A`",
                          icon: "",
                          group: "写作\n组|`B`")
    unsafe.id = "unsafe/action"
    unsafe.isEnabled = true
    let unsafeDescriptors = ActionCommandFactory.descriptors(for: [unsafe]) { _ in nil }
    expect(unsafeDescriptors.first?.title == "润色 # 注入/'A'",
           "action command title keeps unsafe action names single-line")
    expect(unsafeDescriptors.first?.subtitle == "动作 - 写作 组/'B'",
           "action command subtitle keeps unsafe groups single-line")
    expect(unsafeDescriptors.first?.actionID == "unsafe/action",
           "action command keeps the original action id")
    expect(unsafeDescriptors.first?.keywords.contains("\n") == false,
           "action command keywords do not contain newlines")
    expect(unsafeDescriptors.first?.keywords.contains("|") == false &&
           unsafeDescriptors.first?.keywords.contains("`") == false,
           "action command keywords are markdown-safe")
}

func testActionCommandFactoryPrioritizesFrequentActions() {
    var translate = AIAction(name: "翻译", icon: "character.bubble", group: "")
    translate.id = "translate"
    translate.isEnabled = true
    var polish = AIAction(name: "润色", icon: "wand.and.stars", group: "")
    polish.id = "polish"
    polish.isEnabled = true
    var summarize = AIAction(name: "总结", icon: "list.bullet", group: "阅读")
    summarize.id = "summarize"
    summarize.isEnabled = true
    var explain = AIAction(name: "解释", icon: "text.bubble", group: "")
    explain.id = "explain"
    explain.isEnabled = true

    let descriptors = ActionCommandFactory.descriptors(
        for: [translate, polish, summarize, explain],
        usageCounts: ["翻译": 5, "润色": 12, "总结": 5, "解释": -4]
    ) { _ in nil }

    expect(descriptors.map(\.actionID) == ["polish", "translate", "summarize", "explain"],
           "action commands sort frequent actions first and preserve configured order for equal counts")
    expect(descriptors.map(\.usageCount) == [12, 5, 5, 0],
           "action command descriptors expose sanitized usage counts")
    expect(descriptors[0].subtitle == "动作 · 常用 12 次",
           "frequent action command subtitle exposes usage count")
    expect(descriptors[2].subtitle == "动作 - 阅读 · 常用 5 次",
           "frequent grouped action command keeps group context in subtitle")
    expect(descriptors[0].keywords.contains("常用") &&
           descriptors[0].keywords.contains("recent") &&
           descriptors[0].keywords.contains("12"),
           "frequent action command is searchable by usage intent")
    expect(descriptors[3].subtitle == "动作",
           "unused action command keeps the compact default subtitle")
}

func testActionCommandIDsAreStableSlugs() {
    var slash = AIAction(name: "动作一", icon: "", group: "")
    slash.id = "team/A"
    slash.isEnabled = true
    var space = AIAction(name: "动作二", icon: "", group: "")
    space.id = "team A"
    space.isEnabled = true

    let descriptors = ActionCommandFactory.descriptors(for: [slash, space]) { _ in nil }

    expect(descriptors.map(\.id) == ["action-team-A", "action-team-A-2"],
           "action command ids slug action ids and disambiguate collisions")
    expect(descriptors.map(\.actionID) == ["team/A", "team A"],
           "action command keeps original action ids as execution targets")
    expect(descriptors.allSatisfy { !$0.id.contains("/") && !$0.id.contains(" ") },
           "action command ids do not contain path or whitespace separators")
}

func testAutomationActionSelectionNormalizesQueries() {
    var review = AIAction(name: "代码 审查", icon: "", group: "开发")
    review.id = "code-review"
    review.isEnabled = true
    var translate = AIAction(name: "翻译", icon: "", group: "")
    translate.id = "translate/default"
    translate.isEnabled = true
    var disabled = AIAction(name: "禁用 动作", icon: "", group: "")
    disabled.id = "disabled-action"
    disabled.isEnabled = false

    let actions = [review, translate, disabled]

    expect(AutomationActionSelection.resolve(query: "code_review", actions: actions)?.id == "code-review",
           "automation action selection normalizes action id separators")
    expect(AutomationActionSelection.resolve(query: "代码审查", actions: actions)?.id == "code-review",
           "automation action selection normalizes action name whitespace")
    expect(AutomationActionSelection.resolve(query: "translate-default", actions: actions)?.id == "translate/default",
           "automation action selection normalizes action id slashes")
    expect(AutomationActionSelection.resolve(query: "禁用动作", actions: actions) == nil,
           "automation action selection rejects disabled actions")
    expect(AutomationActionSelection.resolve(query: nil, actions: actions) == nil,
           "automation action selection requires a query")
}

func testAutomationSettingsSectionSelectionNormalizesQueries() {
    expect(AutomationSettingsSectionSelection.resolve("AI", fallback: .general) == .ai,
           "settings section selection resolves cased AI alias")
    expect(AutomationSettingsSectionSelection.resolve("api_key", fallback: .general) == .ai,
           "settings section selection normalizes AI key aliases")
    expect(AutomationSettingsSectionSelection.resolve("hot-keys", fallback: .general) == .actions,
           "settings section selection normalizes hotkey aliases")
    expect(AutomationSettingsSectionSelection.resolve("history_records", fallback: .general) == .history,
           "settings section selection normalizes history aliases")
    expect(AutomationSettingsSectionSelection.resolve("screen recording", fallback: .general) == .permission,
           "settings section selection normalizes permission aliases")
    expect(AutomationSettingsSectionSelection.resolve("permission/screen-recording", fallback: .general) == .permission,
           "settings section selection normalizes composite permission aliases")
    expect(AutomationSettingsSectionSelection.resolve("login_item", fallback: .ai) == .permission,
           "settings section selection resolves login item aliases")
    expect(AutomationSettingsSectionSelection.resolve("missing", fallback: .history) == .history,
           "settings section selection falls back for unknown sections")
    expect(AutomationSettingsSectionSelection.resolve(nil, fallback: .actions) == .actions,
           "settings section selection falls back for missing sections")
}

func snapAIURL(host: String, queryItems: [URLQueryItem] = [], path: String = "") -> URL {
    var components = URLComponents()
    components.scheme = "snapai"
    components.host = host
    components.path = path
    components.queryItems = queryItems.isEmpty ? nil : queryItems
    return components.url!
}

func testAutomationURLCommandParsing() {
    let run = snapAIURL(host: "run", queryItems: [
        URLQueryItem(name: "action", value: "润色"),
        URLQueryItem(name: "provider", value: "DeepSeek"),
        URLQueryItem(name: "model", value: "deepseek-chat"),
        URLQueryItem(name: "lang", value: "en"),
        URLQueryItem(name: "replace", value: "true"),
        URLQueryItem(name: "history", value: "false"),
        URLQueryItem(name: "text", value: "  保留空白\n")
    ])
    expect(AutomationURLCommand.parse(run) == .run(
        actionQuery: "润色",
        text: "  保留空白\n",
        options: AutomationRunOptions(providerQuery: "DeepSeek",
                                      modelQuery: "deepseek-chat",
                                      saveHistory: false,
                                      targetLanguage: .english,
                                      replaceByDefault: true)
    ), "parses run URL, preserves text whitespace, and captures run options")

    expect(AutomationURLCommand.parse(URL(string: "snapai://run/%E6%80%BB%E7%BB%93?text=hello")!) == .run(actionQuery: "总结", text: "hello"),
           "parses run URL path as action query")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///run/%E7%BF%BB%E8%AF%91?text=hello")!) == .run(actionQuery: "翻译", text: "hello"),
           "parses path-only run URL path as action query")
    expect(AutomationURLCommand.parse(URL(string: "snapai://run/%E6%80%BB%E7%BB%93?action=%E7%BF%BB%E8%AF%91&text=hello")!) == .run(actionQuery: "翻译", text: "hello"),
           "prefers query action over run path action")

    let snakeCaseRun = snapAIURL(host: "run", queryItems: [
        URLQueryItem(name: "action_id", value: "总结"),
        URLQueryItem(name: "provider_id", value: "OpenAI"),
        URLQueryItem(name: "model-override", value: "gpt-4o-mini"),
        URLQueryItem(name: "target_language", value: "zh"),
        URLQueryItem(name: "replace_by_default", value: "on"),
        URLQueryItem(name: "save_history", value: "no"),
        URLQueryItem(name: "text", value: "hello")
    ])
    expect(AutomationURLCommand.parse(snakeCaseRun) == .run(
        actionQuery: "总结",
        text: "hello",
        options: AutomationRunOptions(providerQuery: "OpenAI",
                                      modelQuery: "gpt-4o-mini",
                                      saveHistory: false,
                                      targetLanguage: .chinese,
                                      replaceByDefault: true)
    ), "normalizes snake_case and kebab-case run option names")

    let boolAliasesRun = snapAIURL(host: "run", queryItems: [
        URLQueryItem(name: "save_history", value: "disabled"),
        URLQueryItem(name: "write_back", value: "enabled"),
        URLQueryItem(name: "text", value: "hello")
    ])
    expect(AutomationURLCommand.parse(boolAliasesRun) == .run(
        actionQuery: nil,
        text: "hello",
        options: AutomationRunOptions(saveHistory: false,
                                      replaceByDefault: true)
    ), "normalizes enabled and disabled boolean aliases")

    let conflictingHistoryRun = snapAIURL(host: "run", queryItems: [
        URLQueryItem(name: "history", value: "true"),
        URLQueryItem(name: "saveHistory", value: "false"),
        URLQueryItem(name: "text", value: "hello")
    ])
    expect(AutomationURLCommand.parse(conflictingHistoryRun) == .run(
        actionQuery: nil,
        text: "hello",
        options: AutomationRunOptions(saveHistory: false)
    ), "explicit false save-history run option wins over conflicting true history aliases")

    let normalizedLanguage = snapAIURL(host: "run", queryItems: [
        URLQueryItem(name: "lang", value: "simplified-chinese"),
        URLQueryItem(name: "text", value: "hello")
    ])
    expect(AutomationURLCommand.parse(normalizedLanguage) == .run(
        actionQuery: nil,
        text: "hello",
        options: AutomationRunOptions(targetLanguage: .chinese)
    ), "normalizes hyphenated target language aliases")

    let japaneseLanguage = snapAIURL(host: "run", queryItems: [
        URLQueryItem(name: "target_language", value: "Japanese"),
        URLQueryItem(name: "text", value: "hello")
    ])
    expect(AutomationURLCommand.parse(japaneseLanguage) == .run(
        actionQuery: nil,
        text: "hello",
        options: AutomationRunOptions(targetLanguage: .japanese)
    ), "normalizes cased target language aliases")

    let koreanLanguage = snapAIURL(host: "run", queryItems: [
        URLQueryItem(name: "language", value: "korean_language"),
        URLQueryItem(name: "text", value: "hello")
    ])
    expect(AutomationURLCommand.parse(koreanLanguage) == .run(
        actionQuery: nil,
        text: "hello",
        options: AutomationRunOptions(targetLanguage: .korean)
    ), "normalizes underscore target language aliases")

    let translate = snapAIURL(host: "translate", queryItems: [
        URLQueryItem(name: "text", value: "hello")
    ])
    expect(AutomationURLCommand.parse(translate) == .run(actionQuery: "翻译", text: "hello"),
           "maps translate URL alias to translation action")

    let quick = snapAIURL(host: "quick", queryItems: [
        URLQueryItem(name: "action", value: "翻译"),
        URLQueryItem(name: "prompt", value: "直接打开输入框")
    ])
    expect(AutomationURLCommand.parse(quick) == .openQuickInput(text: "直接打开输入框", actionQuery: "翻译"),
           "parses quick URL with prefilled prompt and action")
    expect(AutomationURLCommand.parse(URL(string: "snapai://quick/%E6%B6%A6%E8%89%B2?prompt=hello")!) == .openQuickInput(text: "hello", actionQuery: "润色"),
           "parses quick URL path as action query")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///quick/%E6%80%BB%E7%BB%93?prompt=hello")!) == .openQuickInput(text: "hello", actionQuery: "总结"),
           "parses path-only quick URL path as action query")
    expect(AutomationURLCommand.parse(URL(string: "snapai://quick/%E6%B6%A6%E8%89%B2?action=%E7%BF%BB%E8%AF%91&prompt=hello")!) == .openQuickInput(text: "hello", actionQuery: "翻译"),
           "prefers query action over quick path action")
    let quickInputAlias = snapAIURL(host: "quick_input", queryItems: [
        URLQueryItem(name: "prompt", value: "下划线命令")
    ])
    expect(AutomationURLCommand.parse(quickInputAlias) == .openQuickInput(text: "下划线命令", actionQuery: nil),
           "normalizes underscore quick input command names")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///quick%20input?prompt=encoded")!) == .openQuickInput(text: "encoded", actionQuery: nil),
           "normalizes encoded-space path command names")

    let settings = snapAIURL(host: "settings", queryItems: [
        URLQueryItem(name: "section", value: "privacy")
    ])
    expect(AutomationURLCommand.parse(settings) == .openSettings(section: "privacy"),
           "parses settings section")

    let settingsPath = URL(string: "snapai://settings/ai")!
    expect(AutomationURLCommand.parse(settingsPath) == .openSettings(section: "ai"),
           "parses settings section from path when query section is absent")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///settings/ai")!) == .openSettings(section: "ai"),
           "parses settings section from path-only URL")
    expect(AutomationURLCommand.parse(URL(string: "snapai://settings/section/permission")!) == .openSettings(section: "permission"),
           "parses labeled settings section path value")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///settings/tab/screen-recording")!) == .openSettings(section: "screen-recording"),
           "parses path-only labeled settings tab path value")
    expect(AutomationURLCommand.parse(URL(string: "snapai://settings/permission/screen-recording")!) == .openSettings(section: "permission/screen-recording"),
           "preserves composite settings section path values")

    let settingsQueryWins = URL(string: "snapai://settings/history?section=permission")!
    expect(AutomationURLCommand.parse(settingsQueryWins) == .openSettings(section: "permission"),
           "prefers settings query section over path section")

    expect(AutomationURLCommand.parse(URL(string: "snapai://history?clear=true")!) == .clearHistory,
           "parses explicit history clear URL")
    expect(AutomationURLCommand.parse(URL(string: "snapai://history/clear")!) == .clearHistory,
           "parses history clear path subcommand")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///history/delete_all")!) == .clearHistory,
           "parses path-only history delete-all subcommand")
    expect(AutomationURLCommand.parse(URL(string: "snapai://history?delete_all")!) == .clearHistory,
           "normalizes snake_case history delete-all flag")
    expect(AutomationURLCommand.parse(URL(string: "snapai://history/clear?clear=false")!) == .openHistory,
           "explicit false clear query suppresses history clear path subcommands")
    expect(AutomationURLCommand.parse(URL(string: "snapai://history/delete-all?reset=off")!) == .openHistory,
           "explicit off reset query suppresses history reset path subcommands")
    expect(AutomationURLCommand.parse(URL(string: "snapai://history/clear?clear=true&reset=off")!) == .openHistory,
           "explicit false-equivalent history clear parameter wins over conflicting true parameters")
    expect(AutomationURLCommand.parse(URL(string: "snapai://history?clear=true&query=release")!) == .openHistory,
           "does not clear all history when a clear URL also carries a search filter")
    expect(AutomationURLCommand.parse(URL(string: "snapai://history/clear?tag=%E9%A1%B9%E7%9B%AEA")!) == .openHistory,
           "does not clear all history when a clear path also carries a tag filter")
    expect(AutomationURLCommand.parse(URL(string: "snapai://history?delete_all=true&favorite=true")!) == .openHistory,
           "does not clear all history when a clear URL also carries a favorite filter")
    expect(AutomationURLCommand.parse(URL(string: "snapai://history?export=true")!) == .copyHistoryMarkdown(),
           "parses history export URL as copy markdown command")
    expect(AutomationURLCommand.parse(URL(string: "snapai://history/export")!) == .copyHistoryMarkdown(),
           "parses history export path subcommand")
    expect(AutomationURLCommand.parse(URL(string: "snapai://history/export?export=false")!) == .openHistory,
           "explicit false export query suppresses history export path subcommands")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///history/markdown")!) == .copyHistoryMarkdown(),
           "parses path-only history markdown subcommand")
    let filteredHistoryPath = snapAIURL(host: "history", queryItems: [
        URLQueryItem(name: "search", value: "release"),
        URLQueryItem(name: "action_name", value: "总结"),
        URLQueryItem(name: "model", value: "gpt-4o-mini"),
        URLQueryItem(name: "tag", value: "发布"),
        URLQueryItem(name: "favorite", value: nil)
    ], path: "/export")
    expect(AutomationURLCommand.parse(filteredHistoryPath) == .copyHistoryMarkdown(criteria: HistoryFilterCriteria(
        query: "release",
        actionFilter: "总结",
        modelFilter: "gpt-4o-mini",
        tagFilter: "发布",
        favoriteOnly: true
    )), "path history export preserves normalized filter query parameters")
    expect(AutomationURLCommand.parse(URL(string: "snapai://history?copy=true")!) == .copyHistoryMarkdown(),
           "parses history copy URL as copy markdown command")
    expect(AutomationURLCommand.parse(URL(string: "snapai://history?export")!) == .copyHistoryMarkdown(),
           "parses flag-style history export URL as copy markdown command")
    expect(AutomationURLCommand.parse(URL(string: "snapai://history?copy=")!) == .copyHistoryMarkdown(),
           "parses empty-value history copy URL as enabled flag")
    expect(AutomationURLCommand.parse(URL(string: "snapai://history/export?copy=true&export=false")!) == .openHistory,
           "explicit false-equivalent history export parameter wins over conflicting true parameters")
    let filteredHistory = snapAIURL(host: "history", queryItems: [
        URLQueryItem(name: "export", value: "true"),
        URLQueryItem(name: "query", value: "release 诊断"),
        URLQueryItem(name: "action", value: "总结"),
        URLQueryItem(name: "model", value: "gpt-4o-mini"),
        URLQueryItem(name: "tag", value: "发布"),
        URLQueryItem(name: "favorite", value: "true")
    ])
    expect(AutomationURLCommand.parse(filteredHistory) == .copyHistoryMarkdown(criteria: HistoryFilterCriteria(
        query: "release 诊断",
        actionFilter: "总结",
        modelFilter: "gpt-4o-mini",
        tagFilter: "发布",
        favoriteOnly: true
    )), "parses filtered history markdown export URL")
    let filteredHistoryContext = snapAIURL(host: "history", queryItems: [
        URLQueryItem(name: "search", value: "release"),
        URLQueryItem(name: "action", value: "总结"),
        URLQueryItem(name: "model", value: "gpt-4o-mini"),
        URLQueryItem(name: "tag", value: "发布"),
        URLQueryItem(name: "favorite", value: "true"),
        URLQueryItem(name: "name", value: "项目A上下文"),
        URLQueryItem(name: "limit", value: "3"),
        URLQueryItem(name: "max_chars", value: "80")
    ], path: "/context")
    expect(AutomationURLCommand.parse(filteredHistoryContext) == .createHistoryContext(criteria: HistoryFilterCriteria(
        query: "release",
        actionFilter: "总结",
        modelFilter: "gpt-4o-mini",
        tagFilter: "发布",
        favoriteOnly: true
    ), options: AutomationHistoryContextOptions(name: "项目A上下文",
                                                maxEntries: 3,
                                                maxFieldCharacters: 80)), "path history context command preserves filters and context options")
    expect(AutomationURLCommand.parse(URL(string: "snapai://history?create_context=true")!) == .createHistoryContext(),
           "parses snake_case history create-context flag")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///history/create-context-profile?tag=%E9%A1%B9%E7%9B%AEA&profile_name=%E9%A1%B9%E7%9B%AEA%E8%AE%B0%E5%BF%86&entry_limit=2&max_field_chars=120")!) == .createHistoryContext(criteria: HistoryFilterCriteria(tagFilter: "项目A"), options: AutomationHistoryContextOptions(name: "项目A记忆", maxEntries: 2, maxFieldCharacters: 120)),
           "parses path-only history create-context-profile subcommand with snake_case context options")
    expect(AutomationURLCommand.parse(URL(string: "snapai://history/context?export=true")!) == .copyHistoryMarkdown(),
           "history export flag takes precedence over context path command")
    expect(AutomationURLCommand.parse(URL(string: "snapai://history/context?clear=true")!) == .clearHistory,
           "history clear flag takes precedence over context path command")
    expect(AutomationURLCommand.parse(URL(string: "snapai://health")!) == .openPermissionHealth,
           "parses health URL as permission health center")
    expect(AutomationURLCommand.parse(URL(string: "snapai://permission_health")!) == .openPermissionHealth,
           "normalizes underscore permission health command names")
    expect(AutomationURLCommand.parse(URL(string: "snapai://health?copy=true")!) == .copyPermissionDiagnostics,
           "health copy query reuses permission diagnostics copy command")
    expect(AutomationURLCommand.parse(URL(string: "snapai://health?summary=true")!) == .copyBriefPermissionDiagnostics,
           "health summary query reuses brief permission diagnostics command")
    expect(AutomationURLCommand.parse(URL(string: "snapai://health/recovery")!) == .copyPermissionRecoverySuggestions,
           "health recovery path reuses permission recovery suggestions command")
    expect(AutomationURLCommand.parse(URL(string: "snapai://permission_health?suggestions=true")!) == .copyPermissionRecoverySuggestions,
           "permission health suggestions query reuses permission recovery suggestions command")
    expect(AutomationURLCommand.parse(URL(string: "snapai://health/recovery?copy=false")!) == .openPermissionHealth,
           "explicit false copy query suppresses health recovery path subcommands")
    expect(AutomationURLCommand.parse(URL(string: "snapai://diagnostics")!) == .openPermissionHealth,
           "parses diagnostics URL as permission health center")
    expect(AutomationURLCommand.parse(URL(string: "snapai://diagnostics?copy=true")!) == .copyPermissionDiagnostics,
           "parses diagnostics copy URL as copy diagnostics command")
    expect(AutomationURLCommand.parse(URL(string: "snapai://diagnostics?copy")!) == .copyPermissionDiagnostics,
           "parses flag-style diagnostics copy URL")
    expect(AutomationURLCommand.parse(URL(string: "snapai://diagnostics?summary=true")!) == .copyBriefPermissionDiagnostics,
           "parses diagnostics summary query as copy brief diagnostics command")
    expect(AutomationURLCommand.parse(URL(string: "snapai://diagnostics?brief")!) == .copyBriefPermissionDiagnostics,
           "parses flag-style diagnostics brief query")
    expect(AutomationURLCommand.parse(URL(string: "snapai://diagnostics/summary")!) == .copyBriefPermissionDiagnostics,
           "parses diagnostics summary path subcommand")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///diagnostics/copy_summary")!) == .copyBriefPermissionDiagnostics,
           "parses path-only diagnostics copy summary subcommand")
    expect(AutomationURLCommand.parse(URL(string: "snapai://diagnostics/copy?summary=true")!) == .copyBriefPermissionDiagnostics,
           "diagnostics summary query takes precedence over full copy path command")
    expect(AutomationURLCommand.parse(URL(string: "snapai://diagnostics/recovery")!) == .copyPermissionRecoverySuggestions,
           "parses diagnostics recovery path subcommand")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///diagnostics/copy_suggestions")!) == .copyPermissionRecoverySuggestions,
           "parses path-only diagnostics copy suggestions subcommand")
    expect(AutomationURLCommand.parse(URL(string: "snapai://diagnostics?suggestions=true")!) == .copyPermissionRecoverySuggestions,
           "parses diagnostics suggestions query as copy recovery suggestions command")
    expect(AutomationURLCommand.parse(URL(string: "snapai://diagnostics/copy?fix=true")!) == .copyPermissionRecoverySuggestions,
           "diagnostics recovery query takes precedence over full copy path command")
    expect(AutomationURLCommand.parse(URL(string: "snapai://diagnostics/recovery?copy=false")!) == .openPermissionHealth,
           "explicit false copy query suppresses diagnostics recovery path subcommands")
    expect(AutomationURLCommand.parse(URL(string: "snapai://diagnostics/recovery?suggestions=false")!) == .openPermissionHealth,
           "explicit false recovery query suppresses diagnostics recovery path subcommands")
    expect(AutomationURLCommand.parse(URL(string: "snapai://diagnostics/summary?copy=false")!) == .openPermissionHealth,
           "explicit false copy query suppresses diagnostics summary path subcommands")
    expect(AutomationURLCommand.parse(URL(string: "snapai://diagnostics?summary=false&copy=true")!) == .copyPermissionDiagnostics,
           "explicit false summary query falls back to full diagnostics copy when copy is true")
    expect(AutomationURLCommand.parse(URL(string: "snapai://diagnostics/copy")!) == .copyPermissionDiagnostics,
           "parses diagnostics copy path subcommand")
    expect(AutomationURLCommand.parse(URL(string: "snapai://diagnostics/copy?copy=false")!) == .openPermissionHealth,
           "explicit false copy query suppresses diagnostics copy path subcommands")
    expect(AutomationURLCommand.parse(URL(string: "snapai://diagnostics/copy?copy=true&copy=false")!) == .openPermissionHealth,
           "explicit false diagnostics copy parameter wins over conflicting true parameters")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///diagnostics/copy_diagnostics")!) == .copyPermissionDiagnostics,
           "parses path-only diagnostics copy subcommand")
    expect(AutomationURLCommand.parse(URL(string: "snapai://diagnostics?copy_diagnostics")!) == .copyPermissionDiagnostics,
           "normalizes snake_case diagnostics copy flag")
    expect(AutomationURLCommand.parse(URL(string: "snapai://install-log")!) == .revealInstallLog,
           "parses install log URL as reveal latest install log command")
    expect(AutomationURLCommand.parse(URL(string: "snapai://install-log?copy=true")!) == .copyInstallLogPath,
           "parses install log copy URL as copy install log path command")
    expect(AutomationURLCommand.parse(URL(string: "snapai://install_log?copy")!) == .copyInstallLogPath,
           "normalizes underscore install log command names")
    expect(AutomationURLCommand.parse(URL(string: "snapai://install-log?copy_path")!) == .copyInstallLogPath,
           "normalizes snake_case install log copy path flag")
    expect(AutomationURLCommand.parse(URL(string: "snapai://install-log/copy")!) == .copyInstallLogPath,
           "parses install log copy path subcommand")
    expect(AutomationURLCommand.parse(URL(string: "snapai://install-log/copy?copy=false")!) == .revealInstallLog,
           "explicit false copy query suppresses install log copy path subcommands")
    expect(AutomationURLCommand.parse(URL(string: "snapai://install-log/copy?copy_path=true&copy=false")!) == .revealInstallLog,
           "explicit false install log copy parameter wins over conflicting true parameters")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///install-log/copy_path")!) == .copyInstallLogPath,
           "parses path-only install log copy path subcommand")
    expect(AutomationURLCommand.parse(URL(string: "snapai://model?provider=DeepSeek&model=deepseek-chat")!) == .switchModel(providerQuery: "DeepSeek", modelQuery: "deepseek-chat"),
           "parses model switch URL with provider and model query")
    expect(AutomationURLCommand.parse(URL(string: "snapai://model/gpt-4o-mini")!) == .switchModel(providerQuery: nil, modelQuery: "gpt-4o-mini"),
           "parses model switch URL path as model query")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///model/gpt-4o-mini")!) == .switchModel(providerQuery: nil, modelQuery: "gpt-4o-mini"),
           "parses path-only model switch URL argument")
    expect(AutomationURLCommand.parse(URL(string: "snapai://model/OpenAI/gpt-4o-mini")!) == .switchModel(providerQuery: "OpenAI", modelQuery: "gpt-4o-mini"),
           "parses model switch URL provider and model from path")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///model/OpenAI/gpt-4o-mini")!) == .switchModel(providerQuery: "OpenAI", modelQuery: "gpt-4o-mini"),
           "parses path-only model switch provider and model from path")
    expect(AutomationURLCommand.parse(URL(string: "snapai://model/provider/OpenAI/model/gpt-4o-mini")!) == .switchModel(providerQuery: "OpenAI", modelQuery: "gpt-4o-mini"),
           "parses labeled provider and model path values")
    expect(AutomationURLCommand.parse(URL(string: "snapai://model/model/gpt-4o-mini")!) == .switchModel(providerQuery: nil, modelQuery: "gpt-4o-mini"),
           "parses labeled model path value without provider")
    expect(AutomationURLCommand.parse(URL(string: "snapai://model/OpenAI/gpt-4o-mini?provider=DeepSeek&model=deepseek-chat")!) == .switchModel(providerQuery: "DeepSeek", modelQuery: "deepseek-chat"),
           "prefers model query parameters over provider and model path values")
    expect(AutomationURLCommand.parse(URL(string: "snapai://model/openrouter%2Fauto")!) == .switchModel(providerQuery: nil, modelQuery: "openrouter/auto"),
           "preserves encoded slash in model path argument")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///model/openrouter%2Fauto")!) == .switchModel(providerQuery: nil, modelQuery: "openrouter/auto"),
           "preserves encoded slash in path-only model argument")
    expect(AutomationURLCommand.parse(URL(string: "snapai://context?name=项目A")!) == .switchContext(profileQuery: "项目A"),
           "parses context switch URL with profile query")
    expect(AutomationURLCommand.parse(URL(string: "snapai://context/项目A")!) == .switchContext(profileQuery: "项目A"),
           "parses context switch URL path as profile query")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///context/%E9%A1%B9%E7%9B%AEA%2FDocs")!) == .switchContext(profileQuery: "项目A/Docs"),
           "preserves encoded slash in path-only context argument")
    expect(AutomationURLCommand.parse(URL(string: "snapai://context?copy=true")!) == .copyContext(profileQuery: nil),
           "parses context copy URL as copy active context command")
    expect(AutomationURLCommand.parse(URL(string: "snapai://context/项目A?copy=true")!) == .copyContext(profileQuery: "项目A"),
           "parses context copy URL path as profile query")
    expect(AutomationURLCommand.parse(URL(string: "snapai://context/copy")!) == .copyContext(profileQuery: nil),
           "parses context copy path subcommand")
    expect(AutomationURLCommand.parse(URL(string: "snapai://context/copy?copy=false")!) == .switchContext(profileQuery: "copy"),
           "explicit false copy query suppresses context copy path subcommands")
    expect(AutomationURLCommand.parse(URL(string: "snapai://context/copy?copy=true&export=off")!) == .switchContext(profileQuery: "copy"),
           "explicit false-equivalent context copy parameter wins over conflicting true parameters")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///context/copy/%E9%A1%B9%E7%9B%AEA%2FDocs")!) == .copyContext(profileQuery: "项目A/Docs"),
           "parses path-only context copy subcommand with profile argument")
    expect(AutomationURLCommand.parse(URL(string: "snapai://context/copy?name=%E9%A1%B9%E7%9B%AEA")!) == .copyContext(profileQuery: "项目A"),
           "context copy query profile takes precedence over copy path command")
    expect(AutomationURLCommand.parse(URL(string: "snapai://context/effective?copy=true")!) == .copyEffectiveSystemPrompt,
           "parses context effective path as copy effective system prompt")
    expect(AutomationURLCommand.parse(URL(string: "snapai://context/effective?copy=false")!) == .switchContext(profileQuery: "effective"),
           "explicit false copy query suppresses context effective path subcommands")
    expect(AutomationURLCommand.parse(URL(string: "snapai://context?effective_prompt=true")!) == .copyEffectiveSystemPrompt,
           "parses context effective prompt flag as copy effective system prompt")
    expect(AutomationURLCommand.parse(URL(string: "snapai://context/effective?export=off")!) == .switchContext(profileQuery: "effective"),
           "explicit off export query suppresses context effective export path subcommands")
    expect(AutomationURLCommand.parse(URL(string: "snapai://context/status?copy=true")!) == .copyContextStatus,
           "parses context status path as copy context status")
    expect(AutomationURLCommand.parse(URL(string: "snapai://context/status?copy=false")!) == .switchContext(profileQuery: "status"),
           "explicit false copy query suppresses context status path subcommands")
    expect(AutomationURLCommand.parse(URL(string: "snapai://context/status?status=true&copy=false")!) == .switchContext(profileQuery: "status"),
           "explicit false copy parameter wins over conflicting context status true parameters")
    expect(AutomationURLCommand.parse(URL(string: "snapai://context/status?status=false")!) == .switchContext(profileQuery: "status"),
           "explicit false status query suppresses context status path subcommands")
    expect(AutomationURLCommand.parse(URL(string: "snapai://context/status?markdown=false")!) == .switchContext(profileQuery: "status"),
           "explicit false markdown query suppresses context status markdown path subcommands")
    expect(AutomationURLCommand.parse(URL(string: "snapai://context?diagnostics=true")!) == .copyContextStatus,
           "parses context diagnostics flag as copy context status")
    expect(AutomationURLCommand.parse(URL(string: "snapai://prompt?copy=true")!) == .copyEffectiveSystemPrompt,
           "parses prompt copy URL as copy effective system prompt")
    expect(AutomationURLCommand.parse(URL(string: "snapai://prompt?copy=true&copy=false")!) == .openQuickInput(text: nil, actionQuery: nil),
           "explicit false prompt copy parameter wins over conflicting true parameters")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///system-prompt/copy")!) == .copyEffectiveSystemPrompt,
           "parses path-only system-prompt copy URL")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///system-prompt/copy?copy=false")!) == .openSettings(section: "general"),
           "explicit false copy query suppresses system-prompt copy path subcommands")
    expect(AutomationURLCommand.parse(URL(string: "snapai://effective-prompt?export=off")!) == .openSettings(section: "general"),
           "explicit off export query suppresses effective-prompt copy commands")
    expect(AutomationURLCommand.parse(URL(string: "snapai://context?clear=true")!) == .clearContext,
           "parses context clear URL as clear context command")
    expect(AutomationURLCommand.parse(URL(string: "snapai://context?clear")!) == .clearContext,
           "parses flag-style context clear URL")
    expect(AutomationURLCommand.parse(URL(string: "snapai://context/clear")!) == .clearContext,
           "parses context clear path subcommand")
    expect(AutomationURLCommand.parse(URL(string: "snapai://context/clear?clear=false")!) == .switchContext(profileQuery: "clear"),
           "explicit false clear query suppresses context clear path subcommands")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///context/disable")!) == .clearContext,
           "parses path-only context disable subcommand")
    expect(AutomationURLCommand.parse(URL(string: "snapai://context/项目A?clear=true")!) == .clearContext,
           "context clear query takes precedence over path profile")
    expect(AutomationURLCommand.parse(URL(string: "snapai://context/copy?clear=true")!) == .clearContext,
           "context clear query takes precedence over copy path command")
    expect(AutomationURLCommand.parse(URL(string: "snapai://context/status?clear=true")!) == .clearContext,
           "context clear query takes precedence over status path command")
    expect(AutomationURLCommand.parse(URL(string: "snapai://context/clear?name=clear")!) == .switchContext(profileQuery: "clear"),
           "explicit context query can still select a profile named clear")
    expect(AutomationURLCommand.parse(URL(string: "snapai://toggle/privacy-preview?enabled=true")!) == .setToggle(commandQuery: "privacy-preview", enabled: true),
           "parses toggle URL path with explicit enabled value")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///toggle/privacy-preview?enabled=true")!) == .setToggle(commandQuery: "privacy-preview", enabled: true),
           "parses path-only toggle URL argument")
    expect(AutomationURLCommand.parse(URL(string: "snapai://toggle/privacy-preview/on")!) == .setToggle(commandQuery: "privacy-preview", enabled: true),
           "parses toggle path state as enabled value")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///toggle/fallback/off")!) == .setToggle(commandQuery: "fallback", enabled: false),
           "parses path-only toggle path state as disabled value")
    expect(AutomationURLCommand.parse(URL(string: "snapai://toggle/privacy-preview/off?enabled=true")!) == .setToggle(commandQuery: "privacy-preview", enabled: true),
           "prefers toggle query enabled value over path state")
    expect(AutomationURLCommand.parse(URL(string: "snapai://toggle/privacy-preview?enabled=启用")!) == .setToggle(commandQuery: "privacy-preview", enabled: true),
           "parses Chinese enabled boolean aliases")
    expect(AutomationURLCommand.parse(URL(string: "snapai://toggle/privacy-preview?enabled")!) == .setToggle(commandQuery: "privacy-preview", enabled: true),
           "parses flag-style toggle enabled URL")
    expect(AutomationURLCommand.parse(URL(string: "snapai://toggle?name=fallback&enabled=false")!) == .setToggle(commandQuery: "fallback", enabled: false),
           "parses toggle URL query with explicit disabled value")
    expect(AutomationURLCommand.parse(URL(string: "snapai://toggle?name=fallback&enabled=禁用")!) == .setToggle(commandQuery: "fallback", enabled: false),
           "parses Chinese disabled boolean aliases")
    expect(AutomationURLCommand.parse(URL(string: "snapai://toggle/redaction")!) == .setToggle(commandQuery: "redaction", enabled: nil),
           "parses toggle URL without enabled value as toggle intent")
    expect(AutomationURLCommand.parse(URL(string: "snapai://toggle/history-metadata/on")!) == .setToggle(commandQuery: "history-metadata", enabled: true),
           "parses history metadata-only toggle URL path state")
    expect(AutomationURLCommand.parse(URL(string: "snapai://routing?preference=quality")!) == .setRoutingPreference(.quality),
           "parses routing preference URL query")
    expect(AutomationURLCommand.parse(URL(string: "snapai://routing/fastest")!) == .setRoutingPreference(.fastest),
           "parses routing preference URL path")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///routing/fastest")!) == .setRoutingPreference(.fastest),
           "parses path-only routing preference URL argument")
    expect(AutomationURLCommand.parse(URL(string: "snapai://routing/preference/quality")!) == .setRoutingPreference(.quality),
           "parses labeled routing preference path value")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///routing/mode/speed-first")!) == .setRoutingPreference(.fastest),
           "parses path-only labeled routing preference path value")
    expect(AutomationURLCommand.parse(URL(string: "snapai://routing/preference/quality?preference=balanced")!) == .setRoutingPreference(.balanced),
           "prefers routing query value over labeled path value")
    expect(AutomationURLCommand.parse(URL(string: "snapai://routing/unknown")!) == .setRoutingPreference(nil),
           "keeps invalid routing preference as nil for AppDelegate fallback")
    expect(AutomationURLCommand.parse(URL(string: "snapai://work-mode?mode=privacy")!) == .setWorkMode(.privacy),
           "parses work mode URL query")
    expect(AutomationURLCommand.parse(URL(string: "snapai://work-mode/quality")!) == .setWorkMode(.quality),
           "parses work mode URL path")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///work-mode/speed")!) == .setWorkMode(.speed),
           "parses path-only work mode URL argument")
    expect(AutomationURLCommand.parse(URL(string: "snapai://work-mode/preset/standard")!) == .setWorkMode(.standard),
           "parses labeled work mode path value")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///workflow-mode/mode/best_quality")!) == .setWorkMode(.quality),
           "parses path-only labeled work mode path value")
    expect(AutomationURLCommand.parse(URL(string: "snapai://work-mode/privacy?mode=speed")!) == .setWorkMode(.speed),
           "prefers work mode query value over path value")
    expect(AutomationURLCommand.parse(URL(string: "snapai://work-mode/unknown")!) == .setWorkMode(nil),
           "keeps invalid work mode as nil for AppDelegate fallback")
    expect(AutomationURLCommand.parse(URL(string: "snapai://dock?enabled=false")!) == .setDockIcon(false),
           "parses dock icon visibility URL")
    expect(AutomationURLCommand.parse(URL(string: "snapai://dock?enabled=否")!) == .setDockIcon(false),
           "parses no-style Chinese dock boolean alias")
    expect(AutomationURLCommand.parse(URL(string: "snapai://dock/hide")!) == .setDockIcon(false),
           "parses dock hide path state")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///dock/show")!) == .setDockIcon(true),
           "parses path-only dock show path state")
    expect(AutomationURLCommand.parse(URL(string: "snapai://login-item?enabled=true")!) == .setLoginItem(true),
           "parses login item URL")
    expect(AutomationURLCommand.parse(URL(string: "snapai://login-item?enabled=真")!) == .setLoginItem(true),
           "parses true-style Chinese login item boolean alias")
    expect(AutomationURLCommand.parse(URL(string: "snapai://login-item/enable")!) == .setLoginItem(true),
           "parses login item enable path state")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///login-item/disable")!) == .setLoginItem(false),
           "parses path-only login item disable path state")
    expect(AutomationURLCommand.parse(URL(string: "snapai://typewriter?speed=off")!) == .setTypewriterSpeed(.off),
           "parses typewriter speed query")
    expect(AutomationURLCommand.parse(URL(string: "snapai://typewriter/fast")!) == .setTypewriterSpeed(.fast),
           "parses typewriter speed path")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///typewriter/fast")!) == .setTypewriterSpeed(.fast),
           "parses path-only typewriter speed argument")
    expect(AutomationURLCommand.parse(URL(string: "snapai://typewriter/speed/normal")!) == .setTypewriterSpeed(.normal),
           "parses labeled typewriter speed path value")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///typewriter/mode/standard_speed")!) == .setTypewriterSpeed(.normal),
           "parses path-only labeled typewriter speed path value")
    expect(AutomationURLCommand.parse(URL(string: "snapai://typewriter/speed/fast?speed=off")!) == .setTypewriterSpeed(.off),
           "prefers typewriter query speed over labeled path value")
    expect(AutomationURLCommand.parse(URL(string: "snapai://typewriter/unknown")!) == .setTypewriterSpeed(nil),
           "keeps invalid typewriter speed as nil for AppDelegate fallback")
    expect(AutomationURLCommand.parse(URL(string: "snapai://command_palette")!) == .openCommandPalette,
           "normalizes underscore command palette command names")
    expect(AutomationURLCommand.parse(URL(string: "snapai:///command%20palette")!) == .openCommandPalette,
           "normalizes encoded-space command palette path names")
    expect(AutomationURLCommand.parse(URL(string: "snapai://check_updates")!) == .checkUpdates,
           "normalizes underscore check updates command names")

    let emptyRun = snapAIURL(host: "run", queryItems: [
        URLQueryItem(name: "action", value: "总结"),
        URLQueryItem(name: "text", value: "  \n")
    ])
    expect(AutomationURLCommand.parse(emptyRun) == .openQuickInput(text: nil, actionQuery: "总结"),
           "empty run text opens quick input with requested action instead of dispatching an empty request")

    let blankControls = snapAIURL(host: "run", queryItems: [
        URLQueryItem(name: "action", value: "  "),
        URLQueryItem(name: "provider", value: ""),
        URLQueryItem(name: "model", value: " \n "),
        URLQueryItem(name: "text", value: "hello")
    ])
    expect(AutomationURLCommand.parse(blankControls) == .run(actionQuery: nil,
                                                             text: "hello",
                                                             options: .empty),
           "normalizes blank control parameters without trimming payload text")

    expect(AutomationURLCommand.parse(URL(string: "https://example.com")!) == nil,
           "rejects non-SnapAI schemes")
}

func testAutomationWriteBackPolicyRequiresCapturedSelection() {
    let urlReplace = AutomationWriteBackPolicy.urlRun(
        options: AutomationRunOptions(replaceByDefault: true)
    )
    expect(!urlReplace.autoReplaceEnabled,
           "URL automation never enables automatic write-back without a trusted selection context")

    var replacingAction = AIAction.defaults()[2]
    replacingAction.replaceByDefault = true
    expect(AutomationWriteBackPolicy.capturedSelection(action: replacingAction).autoReplaceEnabled,
           "captured selection actions can enter replacement confirmation")

    var plainAction = AIAction.defaults()[0]
    plainAction.replaceByDefault = false
    expect(!AutomationWriteBackPolicy.capturedSelection(action: plainAction).autoReplaceEnabled,
           "captured selection respects actions that do not request replacement")
}

func testAutomationRunOptionsApplyToActionWithoutChangingSettings() {
    let settings = AppSettings()
    var openAI = AIProvider(name: "Open AI", apiProtocol: .openAI,
                            baseURL: "https://openai.test/v1",
                            apiKey: "key",
                            models: [
                                AIModelEntry(name: "gpt-4o-mini"),
                                AIModelEntry(name: "disabled-model", enabled: false)
                            ])
    var deepSeek = AIProvider(name: "DeepSeek", apiProtocol: .openAI,
                              baseURL: "https://deepseek.test/v1",
                              apiKey: "key",
                              models: [AIModelEntry(name: "deepseek-chat")])
    openAI.isEnabled = true
    deepSeek.isEnabled = true
    settings.providers = [openAI, deepSeek]
    settings.activeProviderID = openAI.id
    settings.activeModel = "gpt-4o-mini"

    var action = AIAction.defaults()[0]
    action.saveHistory = true

    let overridden = action.applyingAutomationOptions(
        AutomationRunOptions(providerQuery: "DeepSeek",
                             modelQuery: "deepseek-chat",
                             saveHistory: false,
                             targetLanguage: .japanese,
                             replaceByDefault: true),
        settings: settings
    )
    expect(overridden.providerID == deepSeek.id, "automation provider option resolves by provider name")
    expect(overridden.modelOverride == "deepseek-chat", "automation model option resolves enabled model")
    expect(overridden.saveHistory == false, "automation saveHistory option overrides action history behavior")
    expect(overridden.isTranslation && overridden.targetLanguage == .japanese,
           "automation language option sets a one-shot translation target")
    expect(overridden.replaceByDefault, "automation replace option overrides default replacement confirmation flag")
    expect(action.providerID == nil &&
           action.modelOverride == nil &&
           action.saveHistory == true &&
           action.targetLanguage == .auto &&
           action.replaceByDefault == false,
           "automation options do not mutate the source action")
    expect(settings.activeProviderID == openAI.id && settings.activeModel == "gpt-4o-mini",
           "automation options do not mutate global active model settings")

    let disabledModel = action.applyingAutomationOptions(
        AutomationRunOptions(providerQuery: "Open AI",
                             modelQuery: "disabled-model",
                             saveHistory: nil),
        settings: settings
    )
    expect(disabledModel.providerID == openAI.id, "automation can still choose the requested provider")
    expect(disabledModel.modelOverride == nil, "automation ignores disabled model overrides")

    let modelOnly = action.applyingAutomationOptions(
        AutomationRunOptions(providerQuery: nil,
                             modelQuery: "deepseek-chat",
                             saveHistory: nil),
        settings: settings
    )
    expect(modelOnly.providerID == deepSeek.id && modelOnly.modelOverride == "deepseek-chat",
           "automation can infer provider from model when provider is omitted")

    let normalizedLookup = action.applyingAutomationOptions(
        AutomationRunOptions(providerQuery: "openai",
                             modelQuery: "gpt4omini",
                             saveHistory: nil),
        settings: settings
    )
    expect(normalizedLookup.providerID == openAI.id && normalizedLookup.modelOverride == "gpt-4o-mini",
           "automation options normalize provider and model lookup separators")

    let invalidProvider = action.applyingAutomationOptions(
        AutomationRunOptions(providerQuery: "MissingProvider",
                             modelQuery: "deepseek-chat",
                             saveHistory: nil),
        settings: settings
    )
    expect(invalidProvider.providerID == nil && invalidProvider.modelOverride == nil,
           "automation does not infer provider from model when an explicit provider query is invalid")
}

func testAutomationModelSelectionResolvesEnabledModelsOnly() {
    let settings = AppSettings()
    var openAI = AIProvider(name: "Open AI", apiProtocol: .openAI,
                            baseURL: "https://openai.test/v1",
                            apiKey: "key",
                            models: [
                                AIModelEntry(name: "gpt-4o-mini"),
                                AIModelEntry(name: "disabled-model", enabled: false)
                            ])
    var deepSeek = AIProvider(name: "DeepSeek", apiProtocol: .openAI,
                              baseURL: "https://deepseek.test/v1",
                              apiKey: "key",
                              models: [AIModelEntry(name: "deepseek-chat")])
    openAI.isEnabled = true
    deepSeek.isEnabled = true
    settings.providers = [openAI, deepSeek]

    let explicit = AutomationModelSelection.resolve(providerQuery: "DeepSeek",
                                                    modelQuery: "deepseek-chat",
                                                    settings: settings)
    expect(explicit == AutomationModelSelection(providerID: deepSeek.id, modelName: "deepseek-chat"),
           "model selection resolves explicit provider and enabled model")

    let modelOnly = AutomationModelSelection.resolve(providerQuery: nil,
                                                     modelQuery: "deepseek-chat",
                                                     settings: settings)
    expect(modelOnly == AutomationModelSelection(providerID: deepSeek.id, modelName: "deepseek-chat"),
           "model selection can infer provider from model when provider is omitted")

    let normalized = AutomationModelSelection.resolve(providerQuery: "openai",
                                                      modelQuery: "gpt4omini",
                                                      settings: settings)
    expect(normalized == AutomationModelSelection(providerID: openAI.id, modelName: "gpt-4o-mini"),
           "model selection normalizes provider and model separators")

    let normalizedModelOnly = AutomationModelSelection.resolve(providerQuery: nil,
                                                               modelQuery: "deepseekchat",
                                                               settings: settings)
    expect(normalizedModelOnly == AutomationModelSelection(providerID: deepSeek.id, modelName: "deepseek-chat"),
           "model selection can infer provider from normalized model query")

    expect(AutomationModelSelection.resolve(providerQuery: "MissingProvider",
                                            modelQuery: "deepseek-chat",
                                            settings: settings) == nil,
           "model selection does not infer provider when explicit provider is invalid")
    expect(AutomationModelSelection.resolve(providerQuery: "OpenAI",
                                            modelQuery: "disabled-model",
                                            settings: settings) == nil,
           "model selection rejects disabled models")
    expect(AutomationModelSelection.resolve(providerQuery: nil,
                                            modelQuery: nil,
                                            settings: settings) == nil,
           "model selection requires a model query")
}

func testAutomationContextSelectionRequiresEnabledNonEmptyProfile() {
    let settings = AppSettings()
    let enabled = ContextProfile(id: "project-a",
                                 name: "项目A",
                                 content: "术语: SnapAI",
                                 isEnabled: true)
    let spacedName = ContextProfile(id: "project-docs",
                                    name: "项目 A Docs",
                                    content: "文档上下文",
                                    isEnabled: true)
    let disabled = ContextProfile(id: "project-b",
                                  name: "项目B",
                                  content: "禁用内容",
                                  isEnabled: false)
    let empty = ContextProfile(id: "project-c",
                               name: "项目C",
                               content: " \n ",
                               isEnabled: true)
    settings.contextProfiles = [enabled, spacedName, disabled, empty]

    expect(AutomationContextSelection.resolve(profileQuery: "项目A", settings: settings) == AutomationContextSelection(profileID: "project-a"),
           "context selection resolves enabled non-empty profile by name")
    expect(AutomationContextSelection.resolve(profileQuery: "project-a", settings: settings) == AutomationContextSelection(profileID: "project-a"),
           "context selection resolves enabled non-empty profile by id")
    expect(AutomationContextSelection.resolve(profileQuery: "project_docs", settings: settings) == AutomationContextSelection(profileID: "project-docs"),
           "context selection normalizes profile id separators")
    expect(AutomationContextSelection.resolve(profileQuery: "项目ADocs", settings: settings) == AutomationContextSelection(profileID: "project-docs"),
           "context selection normalizes profile name whitespace")
    expect(AutomationContextSelection.resolve(profileQuery: "项目B", settings: settings) == nil,
           "context selection rejects disabled profiles")
    expect(AutomationContextSelection.resolve(profileQuery: "项目C", settings: settings) == nil,
           "context selection rejects empty profiles that would not affect prompts")
    expect(AutomationContextSelection.resolve(profileQuery: nil, settings: settings) == nil,
           "context selection requires a profile query")
}

func testAutomationContextClearRestoresBasePrompt() {
    let settings = AppSettings()
    let profile = ContextProfile(id: "project-a",
                                 name: "项目A",
                                 content: "术语: SnapAI",
                                 isEnabled: true)
    settings.systemPrompt = "基础提示"
    settings.contextProfiles = [profile]
    settings.activeContextProfileID = profile.id
    expect(settings.effectiveSystemPrompt.contains("术语"), "fixture starts with active context")

    settings.activeContextProfileID = ""
    expect(settings.effectiveSystemPrompt == "基础提示",
           "clearing active context restores the base system prompt")
}

func testAutomationRoutingPreferenceSelectionResolvesAliases() {
    expect(AutomationRoutingPreferenceSelection.resolve("fast") == .fastest,
           "resolves fast alias")
    expect(AutomationRoutingPreferenceSelection.resolve("balanced") == .balanced,
           "resolves balanced alias")
    expect(AutomationRoutingPreferenceSelection.resolve("quality") == .quality,
           "resolves quality alias")
    expect(AutomationRoutingPreferenceSelection.resolve("speed first") == .fastest,
           "resolves spaced speed-first alias")
    expect(AutomationRoutingPreferenceSelection.resolve("best_quality") == .quality,
           "resolves underscore best-quality alias")
    expect(AutomationRoutingPreferenceSelection.resolve("best-quality") == .quality,
           "resolves hyphenated best-quality alias")
    expect(AutomationRoutingPreferenceSelection.resolve("最快") == .fastest,
           "resolves Chinese fast alias")
    expect(AutomationRoutingPreferenceSelection.resolve("最佳质量") == .quality,
           "resolves Chinese quality alias")
    expect(AutomationRoutingPreferenceSelection.resolve("missing") == nil,
           "rejects unknown routing preference")
    expect(AutomationRoutingPreferenceSelection.resolve(nil) == nil,
           "requires a routing preference query")
}

func testAutomationWorkModeSelectionResolvesAliases() {
    expect(AutomationWorkModeSelection.resolve("standard") == .standard,
           "resolves standard work mode")
    expect(AutomationWorkModeSelection.resolve("default") == .standard,
           "resolves default work mode alias")
    expect(AutomationWorkModeSelection.resolve("隐私") == .privacy,
           "resolves Chinese privacy work mode")
    expect(AutomationWorkModeSelection.resolve("private") == .privacy,
           "resolves private work mode alias")
    expect(AutomationWorkModeSelection.resolve("fastest") == .speed,
           "resolves fastest work mode alias")
    expect(AutomationWorkModeSelection.resolve("极速") == .speed,
           "resolves Chinese speed work mode")
    expect(AutomationWorkModeSelection.resolve("best_quality") == .quality,
           "resolves underscore quality work mode alias")
    expect(AutomationWorkModeSelection.resolve("质量模式") == .quality,
           "resolves full Chinese quality work mode title")
    expect(AutomationWorkModeSelection.resolve("missing") == nil,
           "rejects unknown work mode")
    expect(AutomationWorkModeSelection.resolve(nil) == nil,
           "requires a work mode query")
}

func testAutomationTypewriterSpeedSelectionResolvesAliases() {
    expect(AutomationTypewriterSpeedSelection.resolve("off") == .off,
           "resolves off typewriter speed")
    expect(AutomationTypewriterSpeedSelection.resolve("standard speed") == .normal,
           "resolves spaced standard speed alias")
    expect(AutomationTypewriterSpeedSelection.resolve("standard_speed") == .normal,
           "resolves underscore standard speed alias")
    expect(AutomationTypewriterSpeedSelection.resolve("normal") == .normal,
           "resolves normal typewriter speed")
    expect(AutomationTypewriterSpeedSelection.resolve("faster") == .fast,
           "resolves faster typewriter speed")
    expect(AutomationTypewriterSpeedSelection.resolve("2") == .normal,
           "resolves numeric typewriter speed alias")
    expect(AutomationTypewriterSpeedSelection.resolve("missing") == nil,
           "rejects unknown typewriter speed")
    expect(AutomationTypewriterSpeedSelection.resolve(nil) == nil,
           "requires a typewriter speed query")
}

func testAIRouterIncludesFallbackCandidates() {
    let settings = AppSettings()
    var primary = AIProvider(name: "Primary", apiProtocol: .openAI,
                             baseURL: "https://primary.test/v1",
                             apiKey: "key",
                             models: [AIModelEntry(name: "gpt-4o-mini")])
    var fallback = AIProvider(name: "Fallback", apiProtocol: .openAI,
                              baseURL: "https://fallback.test/v1",
                              apiKey: "key",
                              models: [AIModelEntry(name: "claude-sonnet-200k")])
    primary.isEnabled = true
    fallback.isEnabled = true
    settings.providers = [primary, fallback]
    settings.activeProviderID = primary.id
    settings.activeModel = "gpt-4o-mini"
    settings.autoRouteEnabled = true
    settings.fallbackEnabled = true

    let routes = AIRequestRouter.candidates(settings: settings,
                                            action: AIAction.defaults()[0],
                                            sourceText: String(repeating: "长", count: 9_000),
                                            hasImage: false)
    expect(routes.first?.providerID == primary.id, "keeps active route first")
    expect(routes.contains { $0.providerID == fallback.id && $0.modelName == "claude-sonnet-200k" },
           "includes fallback candidate")
}

func testAIRequestDiagnosticsSummary() {
    let primary = AIRequestRoute(providerID: "p1",
                                 providerName: "Primary",
                                 modelName: "fast-model",
                                 reason: "当前模型",
                                 isLocalEndpoint: true)
    let fallback = AIRequestRoute(providerID: "p2",
                                  providerName: "Fallback",
                                  modelName: "safe-model",
                                  reason: "备用模型")
    var diagnostics = AIRequestDiagnostics(actionName: "润色",
                                           sourceCharacterCount: 128,
                                           hasImage: false,
                                           fallbackEnabled: true,
                                           routingPreference: .quality,
                                           candidateCount: 2,
                                           actionPipeline: ActionPipelineDiagnostic(
                                            inputPolicy: "text+image",
                                            privacyPolicy: "preview+local-redaction+history-metadata-only",
                                            outputPolicy: "replace-confirmation",
                                            modelPolicy: "auto-route-local-first"
                                           ),
                                           context: AIRequestContextDiagnostic(
                                            contextProfileCount: 3,
                                            usableContextProfileCount: 1,
                                            activeContextCharacterCount: 42,
                                            globalSystemPromptCharacterCount: 18,
                                            effectiveSystemPromptCharacterCount: 96
                                           ),
                                           payload: AIRequestPayloadDiagnostic(
                                            messageCount: 2,
                                            textCharacterCount: 200,
                                            estimatedTextTokens: 50,
                                            imageAttachmentCount: 1
                                           ),
                                           submissionPrivacy: PrivacySubmissionDiagnostic(
                                            originalCharacterCount: 42,
                                            submittedCharacterCount: 36,
                                            hasImage: true,
                                            redactionEnabled: true,
                                            redactionMatchCount: 2,
                                            invalidRedactionRuleCount: 1,
                                            saveHistoryEnabled: false,
                                            historyContentStorage: .metadataOnly,
                                            previewRequired: true
                                           ),
                                           candidateRoutes: [primary, fallback])
    diagnostics.mark(route: primary,
                     status: .failed,
                     message: String(repeating: "错误详情", count: 80),
                     elapsedMilliseconds: 1_234,
                     outputCharacterCount: 0,
                     fallbackDecision: .decide(fallbackEnabled: true,
                                               hasNextRoute: true,
                                               outputCharacterCount: 0))
    diagnostics.mark(route: fallback,
                     status: .succeeded,
                     elapsedMilliseconds: 80,
                     outputCharacterCount: 256)

    let summary = diagnostics.summaryText
    expect(summary.contains("Action: 润色"), "includes action name")
    expect(summary.contains("Source Characters: 128"), "reports source length instead of source content")
    expect(summary.contains("Pipeline Input: text+image"), "reports action pipeline input")
    expect(summary.contains("Pipeline Privacy: preview+local-redaction+history-metadata-only"),
           "reports action pipeline privacy policy")
    expect(summary.contains("Pipeline Output: replace-confirmation"), "reports action pipeline output policy")
    expect(summary.contains("Pipeline Model: auto-route-local-first"), "reports action pipeline model policy")
    expect(summary.contains("Cloud Fallback Review: confirmation-required; local=1; cloud=1"),
           "reports cloud fallback review when privacy local-first routing has cloud candidates")
    expect(summary.contains("Fallback Enabled: yes"), "reports fallback state")
    expect(summary.contains("Auto Route Enabled: no"), "reports auto routing state")
    expect(summary.contains("Routing Preference: 最佳质量"), "reports routing preference")
    expect(summary.contains("Candidate Fit Issues: all-ok"),
           "reports healthy candidate fit summary")
    expect(summary.contains("Recommended Route: Primary / fast-model - 当前模型 · context 50/8000 tokens ok · image not-required · reasoning not-required"),
           "reports first candidate as recommended route with fit summary")
    expect(summary.contains("Recommended Route Issues: all-ok"),
           "reports healthy recommended route fit summary")
    expect(summary.contains("First Request Route: Primary / fast-model - 当前模型 · context 50/8000 tokens ok · image not-required · reasoning not-required"),
           "reports the first route that will actually be requested")
    expect(summary.contains("First Request Route Issues: all-ok"),
           "reports healthy first request route fit summary")
    expect(summary.contains("Preflight Skipped Routes: disabled"),
           "reports disabled preflight skipping when auto routing is off")
    expect(summary.contains("Attempt Statuses: total=2; failed=1; succeeded=1"),
           "reports aggregate attempt statuses")
    expect(summary.contains("Latest Attempt: Fallback / safe-model (备用模型) -> 成功"),
           "reports the latest attempt near the top of diagnostics")
    expect(summary.contains("Request Outcome: succeeded"),
           "reports successful request outcome")
    expect(summary.contains("Request Recovery: 无需处理"),
           "successful request recovery is actionable and quiet")
    expect(summary.contains("Context Profiles: 3 (usable 1)"), "reports context profile health")
    expect(summary.contains("Active Context: set"), "reports active context presence")
    expect(summary.contains("Active Context Characters: 42"), "reports active context length")
    expect(summary.contains("Global System Prompt Characters: 18"), "reports base system prompt length")
    expect(summary.contains("Effective System Prompt Characters: 96"), "reports effective system prompt length")
    expect(summary.contains("Request Messages: 2"), "reports request message count")
    expect(summary.contains("Request Text Characters: 200"), "reports request text size without content")
    expect(summary.contains("Estimated Text Tokens: 50"), "reports estimated input text tokens")
    expect(summary.contains("Image Attachments: 1"), "reports image attachment count")
    expect(summary.contains("Submission Privacy:"), "includes submission privacy section")
    expect(summary.contains("Original Characters: 42"), "reports original character count")
    expect(summary.contains("Submitted Characters: 36"), "reports submitted character count")
    expect(summary.contains("Attached Image: yes"), "reports attached image state")
    expect(summary.contains("Redaction Matches: 2"), "reports redaction match count")
    expect(summary.contains("Invalid Redaction Rules: 1"), "reports invalid redaction rules")
    expect(summary.contains("Save History: no"), "reports action history policy")
    expect(summary.contains("History Content Storage: 不保存"), "reports effective history content storage")
    expect(summary.contains("Preview Required: yes"), "reports privacy preview policy")
    expect(summary.contains("Candidate Details:"), "includes candidate route details")
    expect(summary.contains("1. Primary / fast-model - 当前模型"), "lists primary candidate route")
    expect(summary.contains("2. Fallback / safe-model - 备用模型"), "lists fallback candidate route")
    expect(summary.contains("context 50/8000 tokens ok"),
           "candidate details include estimated context fit")
    expect(summary.contains("image not-required"),
           "candidate details explain when image capability is not required")
    expect(summary.contains("reasoning not-required"),
           "candidate details explain when reasoning capability is not required")
    expect(summary.contains("Primary / fast-model"), "includes failed primary route")
    expect(summary.contains("Fallback / safe-model"), "includes successful fallback route")
    expect(summary.contains("-> 失败"), "uses localized failed status")
    expect(summary.contains("-> 成功"), "uses localized succeeded status")
    expect(summary.contains("耗时 1.2s"), "includes failed attempt duration")
    expect(summary.contains("耗时 80ms"), "includes successful attempt duration")
    expect(summary.contains("输出 0 字"), "includes failed attempt output character count")
    expect(summary.contains("输出 256 字"), "includes successful attempt output character count")
    expect(summary.contains("Fallback will-try-next"), "includes fallback decision for failed attempts")
    expect(summary.contains("..."), "truncates long error body")

    let shareable = diagnostics.summaryText(includeAttemptMessages: false)
    expect(shareable.contains("Primary / fast-model"), "shareable diagnostics keeps route")
    expect(shareable.contains("耗时 1.2s"), "shareable diagnostics keeps attempt duration")
    expect(shareable.contains("输出 0 字"), "shareable diagnostics keeps output character count")
    expect(shareable.contains("Fallback will-try-next"), "shareable diagnostics keeps fallback decision")
    expect(shareable.contains("Attempt Statuses: total=2; failed=1; succeeded=1"),
           "shareable diagnostics keeps aggregate attempt statuses")
    expect(shareable.contains("Latest Attempt: Fallback / safe-model (备用模型) -> 成功"),
           "shareable diagnostics keeps the latest attempt summary")
    expect(shareable.contains("Request Outcome: succeeded"),
           "shareable diagnostics keeps request outcome")
    expect(shareable.contains("Request Recovery: 无需处理"),
           "shareable diagnostics keeps request recovery")
    expect(!shareable.contains("错误详情"), "shareable diagnostics omits error body")
    expect(diagnostics.briefSummaryText == shareable,
           "brief request diagnostics reuses the shareable diagnostics text")
}

func testAIRequestPayloadDiagnosticEstimatesRequestShape() {
    let messages = [
        ChatMessage(role: .system, content: "system prompt"),
        ChatMessage(role: .user, content: String(repeating: "问", count: 17), imageData: Data([1, 2, 3])),
        ChatMessage(role: .assistant, content: "answer")
    ]

    let diagnostic = AIRequestPayloadDiagnostic.make(messages: messages)
    expect(diagnostic.messageCount == 3,
           "payload diagnostics count request messages")
    expect(diagnostic.textCharacterCount == 36,
           "payload diagnostics sum message text characters without storing content")
    expect(diagnostic.estimatedTextTokens == 9,
           "payload diagnostics estimate text tokens using a stable conservative approximation")
    expect(diagnostic.imageAttachmentCount == 1,
           "payload diagnostics count embedded image attachments")
    expect(diagnostic.summaryLines.contains("Estimated Text Tokens: 9"),
           "payload diagnostics render token estimates in request diagnostics")

    let explicitImage = AIRequestPayloadDiagnostic.make(messages: [ChatMessage(role: .user, content: "")],
                                                        explicitHasImage: true)
    expect(explicitImage.imageAttachmentCount == 1,
           "payload diagnostics preserve explicit image state before image data is attached")
    expect(AIRequestPayloadDiagnostic.estimatedTextTokens(forCharacterCount: -12) == 0,
           "payload diagnostics clamp negative token estimates")
    expect(AIRequestPayloadDiagnostic.estimatedTextTokens(forCharacterCount: 1) == 1,
           "payload diagnostics keep tiny payload token estimates visible")
}

func testAIRequestPayloadDiagnosticReportsContextFit() {
    let route = AIRequestRoute(providerID: "p1",
                               providerName: "OpenAI",
                               modelName: "gpt-4o-mini",
                               reason: "当前模型")
    let payload = AIRequestPayloadDiagnostic(messageCount: 1,
                                             textCharacterCount: 400,
                                             estimatedTextTokens: 100,
                                             imageAttachmentCount: 0)
    expect(payload.contextFitSummary(for: route) == "context 100/128000 tokens ok",
           "payload diagnostics report context fit for candidate routes")
    expect(AIRequestPayloadDiagnostic.contextFitStatus(estimatedTextTokens: 0,
                                                       contextTokens: 8_000) == "ok",
           "context fit treats empty payloads as ok")
    expect(AIRequestPayloadDiagnostic.contextFitStatus(estimatedTextTokens: 7_000,
                                                       contextTokens: 8_000) == "near-limit",
           "context fit reports near-limit payloads")
    expect(AIRequestPayloadDiagnostic.contextFitStatus(estimatedTextTokens: 8_001,
                                                       contextTokens: 8_000) == "over-limit",
           "context fit reports over-limit payloads")
    expect(AIRequestPayloadDiagnostic.contextFitStatus(estimatedTextTokens: 1,
                                                       contextTokens: 0) == "unknown",
           "context fit handles unknown context windows")
    expect(AIRequestPayloadDiagnostic.contextFitSummary(estimatedTextTokens: 210_000,
                                                        modelName: "claude-sonnet-200k",
                                                        providerName: "Anthropic").hasSuffix("over-limit"),
           "context fit uses inferred model context windows")
}

func testAIRequestDiagnosticsReportsCandidateImageFit() {
    let textOnly = AIRequestRoute(providerID: "p1",
                                  providerName: "Primary",
                                  modelName: "text-small",
                                  reason: "当前模型")
    let vision = AIRequestRoute(providerID: "p1",
                                providerName: "Primary",
                                modelName: "gpt-4o-mini",
                                reason: "图片输入优先")
    let payload = AIRequestPayloadDiagnostic(messageCount: 1,
                                             textCharacterCount: 80,
                                             estimatedTextTokens: 20,
                                             imageAttachmentCount: 1)

    expect(payload.imageFitSummary(for: textOnly, hasImage: true) == "image unsupported",
           "payload diagnostics can report image-incompatible candidate routes")
    expect(payload.imageFitSummary(for: vision, hasImage: true) == "image supported",
           "payload diagnostics can report image-capable candidate routes")
    expect(AIRequestPayloadDiagnostic.imageFitSummary(hasImage: false,
                                                      modelName: "text-small",
                                                      providerName: "Primary") == "image not-required",
           "payload diagnostics explain when image capability is irrelevant")

    let diagnostics = AIRequestDiagnostics(actionName: "看图",
                                           sourceCharacterCount: 12,
                                           hasImage: true,
                                           fallbackEnabled: true,
                                           routingPreference: .balanced,
                                           candidateCount: 2,
                                           payload: payload,
                                           candidateRoutes: [textOnly, vision])
    let summary = diagnostics.summaryText
    expect(summary.contains("1. Primary / text-small - 当前模型 · context 20/8000 tokens ok · image unsupported · reasoning not-required"),
           "candidate diagnostics expose image-incompatible routes")
    expect(summary.contains("2. Primary / gpt-4o-mini - 图片输入优先 · context 20/128000 tokens ok · image supported · reasoning not-required"),
           "candidate diagnostics expose image-capable routes")
}

func testAIRequestDiagnosticsReportsCandidateReasoningFit() {
    let basic = AIRequestRoute(providerID: "p1",
                               providerName: "Primary",
                               modelName: "fast-chat",
                               reason: "当前模型")
    let reasoning = AIRequestRoute(providerID: "p1",
                                   providerName: "Primary",
                                   modelName: "deepseek-r1",
                                   reason: "推理任务优先")
    let payload = AIRequestPayloadDiagnostic(messageCount: 1,
                                             textCharacterCount: 120,
                                             estimatedTextTokens: 30,
                                             imageAttachmentCount: 0)

    expect(payload.reasoningFitSummary(for: basic, requiresReasoning: true) == "reasoning unsupported",
           "payload diagnostics can report reasoning-incompatible candidate routes")
    expect(payload.reasoningFitSummary(for: reasoning, requiresReasoning: true) == "reasoning supported",
           "payload diagnostics can report reasoning-capable candidate routes")
    expect(AIRequestPayloadDiagnostic.reasoningFitSummary(requiresReasoning: false,
                                                          modelName: "fast-chat",
                                                          providerName: "Primary") == "reasoning not-required",
           "payload diagnostics explain when reasoning capability is irrelevant")

    let diagnostics = AIRequestDiagnostics(actionName: "深度分析",
                                           actionRequiresReasoning: true,
                                           sourceCharacterCount: 24,
                                           hasImage: false,
                                           fallbackEnabled: true,
                                           routingPreference: .quality,
                                           candidateCount: 2,
                                           payload: payload,
                                           candidateRoutes: [basic, reasoning])
    let summary = diagnostics.summaryText
    expect(summary.contains("1. Primary / fast-chat - 当前模型 · context 30/8000 tokens ok · image not-required · reasoning unsupported"),
           "candidate diagnostics expose reasoning-incompatible routes")
    expect(summary.contains("2. Primary / deepseek-r1 - 推理任务优先 · context 30/8000 tokens ok · image not-required · reasoning supported"),
           "candidate diagnostics expose reasoning-capable routes")
}

func testAIRequestDiagnosticsReportsCandidateFitIssueSummary() {
    let textOnly = AIRequestRoute(providerID: "p1",
                                  providerName: "Primary",
                                  modelName: "tiny-8k",
                                  reason: "当前模型")
    let visionReasoning = AIRequestRoute(providerID: "p1",
                                         providerName: "Primary",
                                         modelName: "gpt-4o-mini-r1-128k",
                                         reason: "推理任务优先")
    let routes = [textOnly, visionReasoning]

    expect(AIRequestPayloadDiagnostic.candidateFitIssueSummary(routes: [],
                                                               estimatedTextTokens: 10,
                                                               hasImage: true,
                                                               requiresReasoning: true) == "none",
           "candidate fit summary handles empty candidate lists")
    expect(AIRequestPayloadDiagnostic.candidateFitIssueSummary(routes: routes,
                                                               estimatedTextTokens: 1_000,
                                                               hasImage: false,
                                                               requiresReasoning: false) == "all-ok",
           "candidate fit summary reports all-ok when current inputs need no special capability")

    let issueSummary = AIRequestPayloadDiagnostic.candidateFitIssueSummary(routes: routes,
                                                                           estimatedTextTokens: 9_000,
                                                                           hasImage: true,
                                                                           requiresReasoning: true)
    expect(issueSummary.contains("context-over-limit=1"),
           "candidate fit summary counts over-limit context candidates")
    expect(issueSummary.contains("image-unsupported=1"),
           "candidate fit summary counts image-incompatible candidates")
    expect(issueSummary.contains("reasoning-unsupported=1"),
           "candidate fit summary counts reasoning-incompatible candidates")
    expect(!issueSummary.contains("gpt-4o-mini-r1-128k"),
           "candidate fit summary does not expose model names")

    let nearLimitSummary = AIRequestPayloadDiagnostic.candidateFitIssueSummary(routes: [textOnly],
                                                                               estimatedTextTokens: 7_000,
                                                                               hasImage: false,
                                                                               requiresReasoning: false)
    expect(nearLimitSummary == "context-near-limit=1",
           "candidate fit summary counts near-limit context candidates")

    let diagnostics = AIRequestDiagnostics(actionName: "分析图片",
                                           actionRequiresReasoning: true,
                                           sourceCharacterCount: 20,
                                           hasImage: true,
                                           fallbackEnabled: true,
                                           routingPreference: .quality,
                                           candidateCount: 2,
                                           payload: AIRequestPayloadDiagnostic(messageCount: 1,
                                                                               textCharacterCount: 36_000,
                                                                               estimatedTextTokens: 9_000,
                                                                               imageAttachmentCount: 1),
                                           candidateRoutes: routes)
    expect(diagnostics.summaryText.contains("Candidate Fit Issues: context-over-limit=1; image-unsupported=1; reasoning-unsupported=1"),
           "request diagnostics include candidate fit issue summary")
}

func testAIRequestDiagnosticsReportsRecommendedRouteSafely() {
    let emptyDiagnostics = AIRequestDiagnostics(actionName: "提问",
                                                sourceCharacterCount: 0,
                                                hasImage: false,
                                                fallbackEnabled: true,
                                                routingPreference: .balanced,
                                                candidateCount: 0,
                                                candidateRoutes: [],
                                                candidateUnavailabilitySummary: AIRequestDiagnostics.noCandidateRouteReasonSummary(providers: []),
                                                candidateUnavailabilityRecoverySuggestion: AIRequestDiagnostics.noCandidateRouteRecoverySuggestion(providers: []))
    expect(emptyDiagnostics.recommendedRouteSummary == "none",
           "recommended route summary handles empty candidates")
    expect(emptyDiagnostics.recommendedRouteIssueSummary == "none",
           "recommended route issue summary handles empty candidates")
    expect(emptyDiagnostics.firstRequestRouteSummary == "none",
           "first request route summary handles empty candidates")
    expect(emptyDiagnostics.firstRequestRouteIssueSummary == "none",
           "first request route issue summary handles empty candidates")
    expect(emptyDiagnostics.preflightSkippedRouteSummary == "disabled",
           "preflight skip summary reports disabled auto routing")
    expect(emptyDiagnostics.attemptStatusSummary == "none",
           "attempt status summary handles missing attempts")
    expect(emptyDiagnostics.latestAttemptSummary() == "none",
           "latest attempt summary handles missing attempts")
    expect(emptyDiagnostics.requestOutcomeSummary == "blocked; no-candidate-routes",
           "request outcome reports blocked state when no candidate routes exist")
    expect(emptyDiagnostics.requestRecoveryCode == "no-candidate-routes",
           "request recovery code reports missing candidate routes")
    expect(emptyDiagnostics.requestRecoverySuggestion == "在 AI 设置中添加并启用供应商",
           "request recovery explains how to fix missing candidate routes")
    expect(emptyDiagnostics.summaryText.contains("Recommended Route: none"),
           "request diagnostics report missing recommended route")
    expect(emptyDiagnostics.summaryText.contains("Recommended Route Issues: none"),
           "request diagnostics report missing recommended route issues")
    expect(emptyDiagnostics.summaryText.contains("First Request Route: none"),
           "request diagnostics report missing first request route")
    expect(emptyDiagnostics.summaryText.contains("First Request Route Issues: none"),
           "request diagnostics report missing first request route issues")
    expect(emptyDiagnostics.summaryText.contains("Preflight Skipped Routes: disabled"),
           "request diagnostics report disabled preflight skipping")
    expect(emptyDiagnostics.summaryText.contains("Candidate Unavailability: no-providers=1"),
           "request diagnostics report why no candidate route exists")
    expect(emptyDiagnostics.summaryText.contains("Candidate Unavailability Recovery: 在 AI 设置中添加并启用供应商"),
           "request diagnostics report candidate unavailability recovery separately")
    expect(emptyDiagnostics.summaryText.contains("Attempt Statuses: none"),
           "request diagnostics report missing attempts")
    expect(emptyDiagnostics.summaryText.contains("Latest Attempt: none"),
           "request diagnostics report missing latest attempt")
    expect(emptyDiagnostics.summaryText.contains("Request Outcome: blocked; no-candidate-routes"),
           "request diagnostics report no-candidate blocked outcome")
    expect(emptyDiagnostics.summaryText.contains("Request Recovery Code: no-candidate-routes"),
           "request diagnostics report no-candidate recovery code")
    expect(emptyDiagnostics.summaryText.contains("Request Recovery: 在 AI 设置中添加并启用供应商"),
           "request diagnostics report no-candidate recovery")

    let unsafeRoute = AIRequestRoute(providerID: "p1",
                                     providerName: "Primary\n/Users/alice api_key=sk-live-secret-value-1234567890",
                                     modelName: "gpt-4o-mini\nsk-live-secret-value-1234567890",
                                     reason: "图片\n原因|`R`")
    let diagnostics = AIRequestDiagnostics(actionName: "看图",
                                           sourceCharacterCount: 20,
                                           hasImage: true,
                                           fallbackEnabled: true,
                                           routingPreference: .balanced,
                                           candidateCount: 1,
                                           payload: AIRequestPayloadDiagnostic(messageCount: 1,
                                                                               textCharacterCount: 80,
                                                                               estimatedTextTokens: 20,
                                                                               imageAttachmentCount: 1),
                                           candidateRoutes: [unsafeRoute])
    let recommended = diagnostics.recommendedRouteSummary
    expect(recommended.contains("Primary"),
           "recommended route summary keeps useful provider metadata")
    expect(recommended.contains("gpt-4o-mini"),
           "recommended route summary keeps useful model metadata")
    expect(recommended.contains("图片 原因/'R'"),
           "recommended route summary keeps sanitized route reason")
    expect(recommended.contains("image supported"),
           "recommended route summary includes candidate fit")
    expect(!recommended.contains("/Users/alice"),
           "recommended route summary redacts user paths")
    expect(!recommended.contains("sk-live-secret-value-1234567890"),
           "recommended route summary redacts secrets")
    expect(!recommended.contains("\n"),
           "recommended route summary stays single-line")
    expect(diagnostics.summaryText.contains("Recommended Route: \(recommended)"),
           "request diagnostics include the safe recommended route summary")
    expect(diagnostics.summaryText.contains("Candidate Unavailability: not-needed"),
           "request diagnostics do not report candidate unavailability when routes exist")
    expect(diagnostics.summaryText.contains("Candidate Unavailability Recovery: not-needed"),
           "request diagnostics do not report candidate unavailability recovery when routes exist")
    expect(diagnostics.requestRecoveryCode == "pending",
           "request recovery code reports pending when routes exist but attempts have not started")
}

func testAIRequestDiagnosticsReportsRecommendedRouteIssues() {
    let problematic = AIRequestRoute(providerID: "p1",
                                     providerName: "Primary",
                                     modelName: "tiny-8k",
                                     reason: "当前模型")
    let saferFallback = AIRequestRoute(providerID: "p1",
                                       providerName: "Primary",
                                       modelName: "gpt-4o-mini-r1-128k",
                                       reason: "备用模型")
    let diagnostics = AIRequestDiagnostics(actionName: "分析图片",
                                           actionRequiresReasoning: true,
                                           sourceCharacterCount: 20,
                                           hasImage: true,
                                           fallbackEnabled: true,
                                           routingPreference: .quality,
                                           candidateCount: 2,
                                           payload: AIRequestPayloadDiagnostic(messageCount: 1,
                                                                               textCharacterCount: 36_000,
                                                                               estimatedTextTokens: 9_000,
                                                                               imageAttachmentCount: 1),
                                           candidateRoutes: [problematic, saferFallback])

    expect(diagnostics.recommendedRouteIssueSummary == "context-over-limit=1; image-unsupported=1; reasoning-unsupported=1",
           "recommended route issue summary focuses only on the first candidate")
    expect(diagnostics.summaryText.contains("Recommended Route Issues: context-over-limit=1; image-unsupported=1; reasoning-unsupported=1"),
           "request diagnostics include recommended route issue summary")

    let healthyDiagnostics = AIRequestDiagnostics(actionName: "分析图片",
                                                  actionRequiresReasoning: true,
                                                  sourceCharacterCount: 20,
                                                  hasImage: true,
                                                  fallbackEnabled: true,
                                                  routingPreference: .quality,
                                                  candidateCount: 2,
                                                  payload: AIRequestPayloadDiagnostic(messageCount: 1,
                                                                                      textCharacterCount: 400,
                                                                                      estimatedTextTokens: 100,
                                                                                      imageAttachmentCount: 1),
                                                  candidateRoutes: [saferFallback, problematic])
    expect(healthyDiagnostics.recommendedRouteIssueSummary == "all-ok",
           "recommended route issue summary reports all-ok for a fitting first candidate")
}

func testAIRequestDiagnosticsReportsFirstRequestRouteAfterSkips() {
    let problematic = AIRequestRoute(providerID: "p1",
                                     providerName: "Primary",
                                     modelName: "tiny-8k",
                                     reason: "当前模型")
    let fallback = AIRequestRoute(providerID: "p2",
                                  providerName: "Fallback",
                                  modelName: "gpt-4o-mini-r1-128k",
                                  reason: "备用模型")
    let payload = AIRequestPayloadDiagnostic(messageCount: 1,
                                             textCharacterCount: 36_000,
                                             estimatedTextTokens: 9_000,
                                             imageAttachmentCount: 1)
    let autoDiagnostics = AIRequestDiagnostics(actionName: "分析图片",
                                               actionRequiresReasoning: true,
                                               sourceCharacterCount: 20,
                                               hasImage: true,
                                               fallbackEnabled: true,
                                               autoRouteEnabled: true,
                                               routingPreference: .quality,
                                               candidateCount: 2,
                                               payload: payload,
                                               candidateRoutes: [problematic, fallback])

    expect(autoDiagnostics.recommendedRouteSummary.hasPrefix("Primary / tiny-8k"),
           "recommended route summary continues to expose the candidate order")
    expect(autoDiagnostics.firstRequestRoute == fallback,
           "first request route follows the actual hard-skip routing behavior")
    expect(autoDiagnostics.firstRequestRouteSummary == "Fallback / gpt-4o-mini-r1-128k - 备用模型 · context 9000/128000 tokens ok · image supported · reasoning supported",
           "first request route summary names the actual first requested fallback")
    expect(autoDiagnostics.firstRequestRouteIssueSummary == "all-ok",
           "first request route issue summary focuses on the actual first requested route")
    expect(autoDiagnostics.summaryText.contains("Auto Route Enabled: yes"),
           "request diagnostics expose auto routing state")
    expect(autoDiagnostics.summaryText.contains("First Request Route: Fallback / gpt-4o-mini-r1-128k - 备用模型"),
           "request diagnostics include the first request route")
    expect(autoDiagnostics.summaryText.contains("First Request Route Issues: all-ok"),
           "request diagnostics include first request route fit issues")
    expect(autoDiagnostics.preflightSkippedRoutes == [problematic],
           "preflight skipped routes include hard-incompatible routes before a later candidate")
    expect(autoDiagnostics.preflightSkippedRouteSummary == "1. Primary / tiny-8k - context-over-limit=1; image-unsupported=1",
           "preflight skipped route summary names skipped routes and hard issues")
    expect(autoDiagnostics.summaryText.contains("Preflight Skipped Routes: 1. Primary / tiny-8k - context-over-limit=1; image-unsupported=1"),
           "request diagnostics include preflight skipped route summary")

    let manyProblematicRoutes = (1...7).map { index in
        AIRequestRoute(providerID: "p\(index)",
                       providerName: "Provider \(index)",
                       modelName: "tiny-8k-\(index)",
                       reason: "备用模型")
    }
    let cappedDiagnostics = AIRequestDiagnostics(actionName: "分析图片",
                                                 actionRequiresReasoning: true,
                                                 sourceCharacterCount: 20,
                                                 hasImage: true,
                                                 fallbackEnabled: true,
                                                 autoRouteEnabled: true,
                                                 routingPreference: .quality,
                                                 candidateCount: 8,
                                                 payload: payload,
                                                 candidateRoutes: manyProblematicRoutes + [fallback])
    expect(cappedDiagnostics.preflightSkippedRoutes.count == 7,
           "preflight skipped routes include all hard-incompatible non-final candidates")
    expect(cappedDiagnostics.firstRequestRoute == fallback,
           "first request route skips every hard-incompatible candidate until the fallback")
    let defaultCappedSummary = cappedDiagnostics.preflightSkippedRouteSummary
    expect(defaultCappedSummary.contains("5. Provider 5 / tiny-8k-5"),
           "default preflight skipped route summary shows the configured number of skipped routes")
    expect(!defaultCappedSummary.contains("Provider 6 / tiny-8k-6"),
           "default preflight skipped route summary omits routes past the display limit")
    expect(defaultCappedSummary.contains("+2 more"),
           "default preflight skipped route summary reports folded skipped routes")
    let customCappedSummary = cappedDiagnostics.preflightSkippedRouteSummary(limit: 3)
    expect(customCappedSummary.contains("3. Provider 3 / tiny-8k-3"),
           "custom preflight skipped route summary respects a smaller display limit")
    expect(!customCappedSummary.contains("Provider 4 / tiny-8k-4"),
           "custom preflight skipped route summary omits routes past the custom display limit")
    expect(customCappedSummary.contains("+4 more"),
           "custom preflight skipped route summary reports folded skipped routes")

    let manualDiagnostics = AIRequestDiagnostics(actionName: "分析图片",
                                                 actionRequiresReasoning: true,
                                                 sourceCharacterCount: 20,
                                                 hasImage: true,
                                                 fallbackEnabled: true,
                                                 autoRouteEnabled: false,
                                                 routingPreference: .quality,
                                                 candidateCount: 2,
                                                 payload: payload,
                                                 candidateRoutes: [problematic, fallback])
    expect(manualDiagnostics.firstRequestRoute == problematic,
           "manual routing reports the selected first candidate as the first request route")
    expect(manualDiagnostics.firstRequestRouteIssueSummary == "context-over-limit=1; image-unsupported=1; reasoning-unsupported=1",
           "manual first request route keeps visible fit issues")
    expect(manualDiagnostics.preflightSkippedRoutes.isEmpty,
           "manual routing does not report preflight skipped routes")
    expect(manualDiagnostics.preflightSkippedRouteSummary == "disabled",
           "manual routing explains that preflight skipping is disabled")

    let finalCandidateDiagnostics = AIRequestDiagnostics(actionName: "分析图片",
                                                         actionRequiresReasoning: true,
                                                         sourceCharacterCount: 20,
                                                         hasImage: true,
                                                         fallbackEnabled: true,
                                                         autoRouteEnabled: true,
                                                         routingPreference: .quality,
                                                         candidateCount: 1,
                                                         payload: payload,
                                                         candidateRoutes: [problematic])
    expect(finalCandidateDiagnostics.firstRequestRoute == problematic,
           "auto routing still reports the final candidate when there is no later fallback to skip to")
    expect(finalCandidateDiagnostics.preflightSkippedRouteSummary == "none",
           "auto routing does not report the final candidate as skipped")
}

func testAIRequestDiagnosticsBuildsRouteDisplayNotesWithIssues() {
    let problematic = AIRequestRoute(providerID: "p1",
                                     providerName: "Primary",
                                     modelName: "tiny-8k",
                                     reason: "当前模型")
    let diagnostics = AIRequestDiagnostics(actionName: "分析图片",
                                           actionRequiresReasoning: true,
                                           sourceCharacterCount: 20,
                                           hasImage: true,
                                           fallbackEnabled: true,
                                           routingPreference: .quality,
                                           candidateCount: 1,
                                           payload: AIRequestPayloadDiagnostic(messageCount: 1,
                                                                               textCharacterCount: 36_000,
                                                                               estimatedTextTokens: 9_000,
                                                                               imageAttachmentCount: 1),
                                           candidateRoutes: [problematic])

    expect(diagnostics.routeIssueSummary(for: problematic) == "context-over-limit=1; image-unsupported=1; reasoning-unsupported=1",
           "route issue summary focuses on one route")
    expect(diagnostics.routeDisplayNote(for: problematic) == "当前模型 · 适配问题: context-over-limit=1; image-unsupported=1; reasoning-unsupported=1",
           "route display note surfaces current route fit issues")

    let healthy = AIRequestRoute(providerID: "p1",
                                 providerName: "Primary",
                                 modelName: "gpt-4o-mini-r1-128k",
                                 reason: "推理任务优先")
    let healthyDiagnostics = AIRequestDiagnostics(actionName: "分析图片",
                                                  actionRequiresReasoning: true,
                                                  sourceCharacterCount: 20,
                                                  hasImage: true,
                                                  fallbackEnabled: true,
                                                  routingPreference: .quality,
                                                  candidateCount: 1,
                                                  payload: AIRequestPayloadDiagnostic(messageCount: 1,
                                                                                      textCharacterCount: 400,
                                                                                      estimatedTextTokens: 100,
                                                                                      imageAttachmentCount: 1),
                                                  candidateRoutes: [healthy])
    expect(healthyDiagnostics.routeDisplayNote(for: healthy) == "推理任务优先",
           "route display note stays concise when the route fits")
}

func testAIRequestDiagnosticsAnnotatesAttemptsWithRouteIssues() {
    let problematic = AIRequestRoute(providerID: "p1",
                                     providerName: "Primary",
                                     modelName: "tiny-8k",
                                     reason: "当前模型")
    var diagnostics = AIRequestDiagnostics(actionName: "分析图片",
                                           actionRequiresReasoning: true,
                                           sourceCharacterCount: 20,
                                           hasImage: true,
                                           fallbackEnabled: true,
                                           routingPreference: .quality,
                                           candidateCount: 1,
                                           payload: AIRequestPayloadDiagnostic(messageCount: 1,
                                                                               textCharacterCount: 36_000,
                                                                               estimatedTextTokens: 9_000,
                                                                               imageAttachmentCount: 1),
                                           candidateRoutes: [problematic])
    diagnostics.mark(route: problematic,
                     status: .failed,
                     message: "route failed",
                     elapsedMilliseconds: 80,
                     outputCharacterCount: 0)

    let summary = diagnostics.summaryText
    expect(summary.contains("Primary / tiny-8k (当前模型) -> 失败"),
           "attempt diagnostics still include route and status")
    expect(summary.contains("Route Issues context-over-limit=1; image-unsupported=1; reasoning-unsupported=1"),
           "attempt diagnostics include route fit issues")
    expect(diagnostics.attemptStatusSummary == "total=1; failed=1",
           "attempt status summary counts failed attempts")
    expect(diagnostics.latestAttemptSummary(includeMessage: true).contains("route failed"),
           "latest attempt summary can include the full error message")
    expect(diagnostics.latestAttemptSummary().contains("Primary / tiny-8k (当前模型) -> 失败"),
           "latest attempt summary defaults to a shareable no-message form")
    expect(!diagnostics.latestAttemptSummary().contains("route failed"),
           "latest attempt summary omits error message by default")
    expect(diagnostics.requestOutcomeSummary == "failed",
           "request outcome reports failed attempts without fallback decisions")
    expect(diagnostics.requestRecoveryCode == "generic-failure",
           "request recovery code reports generic failed attempts without fallback decisions")
    expect(diagnostics.requestRecoverySuggestion == "检查 API Key、网络、模型能力或复制完整请求诊断",
           "request recovery gives a generic next step for failed attempts without fallback decisions")

    let shareable = diagnostics.briefSummaryText
    expect(shareable.contains("Route Issues context-over-limit=1; image-unsupported=1; reasoning-unsupported=1"),
           "brief attempt diagnostics also keep route fit issues")
    expect(shareable.contains("Attempt Statuses: total=1; failed=1"),
           "brief attempt diagnostics include aggregate attempt statuses")
    expect(shareable.contains("Latest Attempt: Primary / tiny-8k (当前模型) -> 失败"),
           "brief attempt diagnostics include the latest attempt without the error body")
    expect(shareable.contains("Request Outcome: failed"),
           "brief attempt diagnostics include failed outcome")
    expect(shareable.contains("Request Recovery Code: generic-failure"),
           "brief attempt diagnostics include stable recovery code")
    expect(shareable.contains("Request Recovery: 检查 API Key、网络、模型能力或复制完整请求诊断"),
           "brief attempt diagnostics include recovery guidance")
    expect(!shareable.contains("route failed"),
           "brief attempt diagnostics still omit error messages")

    let healthy = AIRequestRoute(providerID: "p1",
                                 providerName: "Primary",
                                 modelName: "gpt-4o-mini-r1-128k",
                                 reason: "推理任务优先")
    var healthyDiagnostics = AIRequestDiagnostics(actionName: "分析图片",
                                                  actionRequiresReasoning: true,
                                                  sourceCharacterCount: 20,
                                                  hasImage: true,
                                                  fallbackEnabled: true,
                                                  routingPreference: .quality,
                                                  candidateCount: 1,
                                                  payload: AIRequestPayloadDiagnostic(messageCount: 1,
                                                                                      textCharacterCount: 400,
                                                                                      estimatedTextTokens: 100,
                                                                                      imageAttachmentCount: 1),
                                                  candidateRoutes: [healthy])
    healthyDiagnostics.mark(route: healthy,
                            status: .succeeded,
                            elapsedMilliseconds: 40,
                            outputCharacterCount: 12)
    expect(!healthyDiagnostics.summaryText.contains("· Route Issues"),
           "attempt diagnostics stay concise when the route fits")
}

func testAIRequestDiagnosticsSkipsHardIncompatibleRoutes() {
    let problematic = AIRequestRoute(providerID: "p1",
                                     providerName: "Primary",
                                     modelName: "tiny-8k",
                                     reason: "当前模型")
    let reasoningOnlyIssue = AIRequestRoute(providerID: "p1",
                                            providerName: "Primary",
                                            modelName: "fast-chat",
                                            reason: "当前模型")
    let diagnostics = AIRequestDiagnostics(actionName: "分析图片",
                                           actionRequiresReasoning: true,
                                           sourceCharacterCount: 20,
                                           hasImage: true,
                                           fallbackEnabled: true,
                                           routingPreference: .quality,
                                           candidateCount: 2,
                                           payload: AIRequestPayloadDiagnostic(messageCount: 1,
                                                                               textCharacterCount: 36_000,
                                                                               estimatedTextTokens: 9_000,
                                                                               imageAttachmentCount: 1),
                                           candidateRoutes: [problematic, reasoningOnlyIssue])

    expect(diagnostics.routeHardIssueSummary(for: problematic) == "context-over-limit=1; image-unsupported=1",
           "hard route issue summary includes only likely request-failing issues")
    expect(diagnostics.routeSkipMessage(for: problematic) == "跳过明显不适配路由: context-over-limit=1; image-unsupported=1",
           "route skip message explains hard issues")
    expect(diagnostics.routeSkipRecoveryCode(for: problematic) == "preflight-context-limit-image-unsupported",
           "route skip recovery code reports combined context and image hard issues")
    expect(diagnostics.routeSkipRecoverySuggestion(for: problematic) == "文本超过该模型上下文且模型不支持图片;切换长上下文视觉模型或缩短内容",
           "route skip recovery suggestion explains combined context and image hard issues")
    expect(diagnostics.routeSkipSwitchNote(for: problematic,
                                           nextRoute: reasoningOnlyIssue) == "已跳过 Primary / tiny-8k: context-over-limit=1; image-unsupported=1。正在尝试 Primary / fast-chat",
           "route skip switch note names the skipped route, hard issues, and next route")
    expect(diagnostics.routeSkipSwitchNote(for: problematic,
                                           nextRoute: nil) == "已跳过 Primary / tiny-8k: context-over-limit=1; image-unsupported=1",
           "route skip switch note handles missing next route defensively")
    expect(diagnostics.shouldSkipRouteBeforeRequest(problematic,
                                                    autoRouteEnabled: true,
                                                    hasNextRoute: true),
           "auto routing skips hard-incompatible routes when a later route exists")
    var statusDiagnostics = diagnostics
    statusDiagnostics.mark(route: problematic,
                           status: .skipped,
                           message: statusDiagnostics.routeSkipMessage(for: problematic))
    statusDiagnostics.mark(route: reasoningOnlyIssue,
                           status: .running)
    expect(statusDiagnostics.attemptStatusSummary == "total=2; running=1; skipped=1",
           "attempt status summary counts running and skipped attempts in stable order")
    expect(statusDiagnostics.summaryText.contains("Latest Attempt: Primary / fast-chat (当前模型) -> 进行中"),
           "request diagnostics expose the latest running fallback attempt")
    expect(statusDiagnostics.requestOutcomeSummary == "running",
           "request outcome reports running latest attempts")
    expect(statusDiagnostics.requestRecoveryCode == "waiting-current-route",
           "request recovery code follows the latest running attempt")
    expect(statusDiagnostics.requestRecoverySuggestion == "等待当前模型返回",
           "request recovery explains running latest attempts")

    var skippedOnlyDiagnostics = diagnostics
    skippedOnlyDiagnostics.mark(route: problematic,
                                status: .skipped,
                                message: skippedOnlyDiagnostics.routeSkipMessage(for: problematic))
    expect(skippedOnlyDiagnostics.requestOutcomeSummary == "skipped",
           "request outcome reports skipped when the latest attempt was skipped")
    expect(skippedOnlyDiagnostics.requestRecoveryCode == "preflight-context-limit-image-unsupported",
           "request recovery code reports the skipped route hard issues")
    expect(skippedOnlyDiagnostics.requestRecoverySuggestion == "文本超过该模型上下文且模型不支持图片;切换长上下文视觉模型或缩短内容",
           "request recovery explains the skipped route hard issues")
    expect(skippedOnlyDiagnostics.briefSummaryText.contains("Request Recovery Code: preflight-context-limit-image-unsupported"),
           "brief diagnostics include specific skipped route recovery code")
    expect(skippedOnlyDiagnostics.briefSummaryText.contains("Request Recovery: 文本超过该模型上下文且模型不支持图片;切换长上下文视觉模型或缩短内容"),
           "brief diagnostics include specific skipped route recovery suggestion")

    let contextOnlyDiagnostics = AIRequestDiagnostics(actionName: "长文总结",
                                                      sourceCharacterCount: 20,
                                                      hasImage: false,
                                                      fallbackEnabled: true,
                                                      routingPreference: .quality,
                                                      candidateCount: 1,
                                                      payload: AIRequestPayloadDiagnostic(messageCount: 1,
                                                                                          textCharacterCount: 36_000,
                                                                                          estimatedTextTokens: 9_000,
                                                                                          imageAttachmentCount: 0),
                                                      candidateRoutes: [problematic])
    expect(contextOnlyDiagnostics.routeSkipRecoveryCode(for: problematic) == "preflight-context-limit",
           "route skip recovery code reports context-only hard issues")
    expect(contextOnlyDiagnostics.routeSkipRecoverySuggestion(for: problematic) == "文本超过该模型上下文限制;缩短内容或切换长上下文模型",
           "route skip recovery suggestion explains context-only hard issues")

    let imageOnlyDiagnostics = AIRequestDiagnostics(actionName: "分析图片",
                                                    sourceCharacterCount: 20,
                                                    hasImage: true,
                                                    fallbackEnabled: true,
                                                    routingPreference: .quality,
                                                    candidateCount: 1,
                                                    payload: AIRequestPayloadDiagnostic(messageCount: 1,
                                                                                        textCharacterCount: 400,
                                                                                        estimatedTextTokens: 100,
                                                                                        imageAttachmentCount: 1),
                                                    candidateRoutes: [reasoningOnlyIssue])
    expect(imageOnlyDiagnostics.routeSkipRecoveryCode(for: reasoningOnlyIssue) == "preflight-image-unsupported",
           "route skip recovery code reports image-only hard issues")
    expect(imageOnlyDiagnostics.routeSkipRecoverySuggestion(for: reasoningOnlyIssue) == "当前模型不支持图片;切换支持视觉的模型或移除图片",
           "route skip recovery suggestion explains image-only hard issues")
    expect(!diagnostics.shouldSkipRouteBeforeRequest(problematic,
                                                     autoRouteEnabled: false,
                                                     hasNextRoute: true),
           "manual routing does not skip the selected hard-incompatible route")
    expect(!diagnostics.shouldSkipRouteBeforeRequest(problematic,
                                                     autoRouteEnabled: true,
                                                     hasNextRoute: false),
           "routing does not skip the final candidate")

    let reasoningDiagnostics = AIRequestDiagnostics(actionName: "深度分析",
                                                    actionRequiresReasoning: true,
                                                    sourceCharacterCount: 20,
                                                    hasImage: false,
                                                    fallbackEnabled: true,
                                                    routingPreference: .quality,
                                                    candidateCount: 1,
                                                    payload: AIRequestPayloadDiagnostic(messageCount: 1,
                                                                                        textCharacterCount: 400,
                                                                                        estimatedTextTokens: 100,
                                                                                        imageAttachmentCount: 0),
                                                    candidateRoutes: [reasoningOnlyIssue])
    expect(reasoningDiagnostics.routeIssueSummary(for: reasoningOnlyIssue) == "reasoning-unsupported=1",
           "normal route issue summary still reports reasoning mismatch")
    expect(reasoningDiagnostics.routeHardIssueSummary(for: reasoningOnlyIssue) == "all-ok",
           "reasoning mismatch alone is not treated as a hard skip issue")
    expect(!reasoningDiagnostics.shouldSkipRouteBeforeRequest(reasoningOnlyIssue,
                                                              autoRouteEnabled: true,
                                                              hasNextRoute: true),
           "routing does not skip routes only because reasoning capability is weaker")

    var unavailableDiagnostics = reasoningDiagnostics
    unavailableDiagnostics.mark(route: reasoningOnlyIssue,
                                status: .skipped,
                                message: "路由模型不可用或供应商已禁用")
    expect(AIRequestDiagnostics.isRouteConfigurationSkipMessage("路由模型不可用或供应商已禁用"),
           "route configuration skip messages are classified explicitly")
    expect(unavailableDiagnostics.requestRecoveryCode == "route-unavailable",
           "skipped route diagnostics report unavailable route configuration")
    expect(unavailableDiagnostics.requestRecoverySuggestion == "在 AI 设置中重新启用供应商或模型,或切换当前模型",
           "skipped route diagnostics explain unavailable route configuration")
    expect(unavailableDiagnostics.summaryText.contains("Request Recovery Code: route-unavailable"),
           "request diagnostics include unavailable route recovery code")
    expect(unavailableDiagnostics.summaryText.contains("Request Recovery: 在 AI 设置中重新启用供应商或模型,或切换当前模型"),
           "request diagnostics include unavailable route recovery suggestion")
}

func testAIRequestFallbackDecisionExplainsSkippedFallbacks() {
    let disabled = AIRequestFallbackDecision.decide(fallbackEnabled: false,
                                                    hasNextRoute: true,
                                                    outputCharacterCount: 0)
    expect(!disabled.shouldTryNext, "disabled fallback decision does not try next route")
    expect(disabled.diagnosticCode == "disabled", "disabled fallback decision has stable diagnostic code")

    let noNext = AIRequestFallbackDecision.decide(fallbackEnabled: true,
                                                  hasNextRoute: false,
                                                  outputCharacterCount: 0)
    expect(!noNext.shouldTryNext, "missing fallback route does not try next route")
    expect(noNext.diagnosticCode == "no-next-route", "missing fallback route has stable diagnostic code")

    let partial = AIRequestFallbackDecision.decide(fallbackEnabled: true,
                                                   hasNextRoute: true,
                                                   outputCharacterCount: 12)
    expect(!partial.shouldTryNext, "partial output prevents automatic fallback")
    expect(partial.diagnosticCode == "partial-output", "partial output fallback decision is explicit")
    expect(partial.userNote == "已收到部分输出，未自动切换",
           "partial output fallback decision provides a short user note")

    let eligible = AIRequestFallbackDecision.decide(fallbackEnabled: true,
                                                    hasNextRoute: true,
                                                    outputCharacterCount: 0)
    expect(eligible.shouldTryNext, "empty failed output can try next fallback route")
    expect(eligible.diagnosticCode == "will-try-next", "eligible fallback has stable diagnostic code")

    let cloudConfirmation = AIRequestFallbackDecision.decide(fallbackEnabled: true,
                                                             hasNextRoute: true,
                                                             outputCharacterCount: 0,
                                                             requiresCloudFallbackConfirmation: true)
    expect(!cloudConfirmation.shouldTryNext,
           "privacy cloud fallback confirmation prevents silent fallback")
    expect(cloudConfirmation.diagnosticCode == "cloud-confirmation-required",
           "privacy cloud fallback confirmation has stable diagnostic code")
    expect(cloudConfirmation.userNote == "本地模型失败;改用云端备用模型前需要确认",
           "privacy cloud fallback confirmation provides a short user note")

    let route = AIRequestRoute(providerID: "p1",
                               providerName: "Primary",
                               modelName: "fast-model",
                               reason: "当前模型")
    func failedDiagnostics(decision: AIRequestFallbackDecision,
                           message: String = "failed") -> AIRequestDiagnostics {
        var diagnostics = AIRequestDiagnostics(actionName: "提问",
                                               sourceCharacterCount: 12,
                                               hasImage: false,
                                               fallbackEnabled: true,
                                               routingPreference: .balanced,
                                               candidateCount: 1,
                                               candidateRoutes: [route])
        diagnostics.mark(route: route,
                         status: .failed,
                         message: message,
                         outputCharacterCount: decision.reason == .partialOutput ? 12 : 0,
                         fallbackDecision: decision)
        return diagnostics
    }

    let disabledDiagnostics = failedDiagnostics(decision: disabled)
    expect(disabledDiagnostics.requestOutcomeSummary == "failed; fallback=disabled",
           "request outcome exposes disabled fallback decisions")
    expect(disabledDiagnostics.requestRecoveryCode == "fallback-disabled",
           "request recovery code exposes disabled fallback decisions")
    expect(disabledDiagnostics.requestRecoverySuggestion == "开启 fallback 或切换可用模型后重试",
           "request recovery explains disabled fallback decisions")

    let noNextDiagnostics = failedDiagnostics(decision: noNext)
    expect(noNextDiagnostics.requestOutcomeSummary == "failed; fallback=no-next-route",
           "request outcome exposes missing fallback route decisions")
    expect(noNextDiagnostics.requestRecoveryCode == "fallback-no-next-route",
           "request recovery code exposes missing fallback route decisions")
    expect(noNextDiagnostics.requestRecoverySuggestion == "启用备用供应商或模型后重试",
           "request recovery explains missing fallback route decisions")

    let authNoNextDiagnostics = failedDiagnostics(decision: noNext,
                                                 message: "请求失败 (HTTP 401): invalid_api_key")
    expect(authNoNextDiagnostics.requestRecoveryCode == "api-key",
           "request recovery code prefers concrete auth guidance when the final attempt reports an API key failure")
    expect(authNoNextDiagnostics.requestRecoverySuggestion == "在 AI 设置中重新填写 API Key,并确认供应商账号可用",
           "request recovery prefers concrete auth guidance when the final attempt reports an API key failure")
    expect(authNoNextDiagnostics.briefSummaryText.contains("Request Recovery Code: api-key"),
           "brief request diagnostics expose concrete auth recovery code")
    expect(authNoNextDiagnostics.briefSummaryText.contains("Request Recovery: 在 AI 设置中重新填写 API Key,并确认供应商账号可用"),
           "brief request diagnostics expose concrete auth recovery guidance")

    let partialDiagnostics = failedDiagnostics(decision: partial)
    expect(partialDiagnostics.requestOutcomeSummary == "failed; fallback=partial-output",
           "request outcome exposes partial-output fallback decisions")
    expect(partialDiagnostics.requestRecoveryCode == "fallback-partial-output",
           "request recovery code exposes partial-output fallback decisions")
    expect(partialDiagnostics.requestRecoverySuggestion == "已收到部分输出;可复制结果或手动重试",
           "request recovery explains partial-output fallback decisions")

    let eligibleDiagnostics = failedDiagnostics(decision: eligible)
    expect(eligibleDiagnostics.requestOutcomeSummary == "failed; fallback=will-try-next",
           "request outcome exposes pending fallback retry decisions")
    expect(eligibleDiagnostics.requestRecoveryCode == "fallback-will-try-next",
           "request recovery code exposes pending fallback retry decisions")
    expect(eligibleDiagnostics.requestRecoverySuggestion == "等待备用模型尝试",
           "request recovery explains pending fallback retry decisions")

    let cloudDiagnostics = failedDiagnostics(decision: cloudConfirmation)
    expect(cloudDiagnostics.requestOutcomeSummary == "failed; fallback=cloud-confirmation-required",
           "request outcome exposes privacy cloud fallback confirmation")
    expect(cloudDiagnostics.requestRecoveryCode == "fallback-cloud-confirmation-required",
           "request recovery code exposes privacy cloud fallback confirmation")
    expect(cloudDiagnostics.requestRecoverySuggestion.contains("本地模型失败"),
           "request recovery explains privacy cloud fallback confirmation")
}

func testVisibleErrorRecoverySuggestionText() {
    let route = AIRequestRoute(providerID: "p1",
                               providerName: "Primary",
                               modelName: "fast-model",
                               reason: "当前模型")
    var failed = AIRequestDiagnostics(actionName: "提问",
                                      sourceCharacterCount: 12,
                                      hasImage: false,
                                      fallbackEnabled: false,
                                      routingPreference: .balanced,
                                      candidateCount: 1,
                                      candidateRoutes: [route])
    failed.mark(route: route,
                status: .failed,
                message: "failed",
                outputCharacterCount: 0,
                fallbackDecision: .decide(fallbackEnabled: false,
                                          hasNextRoute: true,
                                          outputCharacterCount: 0))

    expect(AIRequestDiagnostics.visibleErrorRecoverySuggestion(diagnostics: failed,
                                                               errorMessage: "HTTP 401") == "在 AI 设置中重新填写 API Key,并确认供应商账号可用",
           "visible recovery helper prefers concrete visible error guidance")
    expect(AIRequestDiagnostics.visibleErrorRecoveryCode(diagnostics: failed,
                                                         errorMessage: "HTTP 401") == "api-key",
           "visible recovery code prefers concrete visible error guidance")
    expect(AIRequestDiagnostics.visibleErrorRecoverySuggestion(diagnostics: failed,
                                                               errorMessage: nil) == nil,
           "visible recovery helper hides recovery text when no error is visible")
    expect(AIRequestDiagnostics.visibleErrorRecoveryCode(diagnostics: failed,
                                                         errorMessage: nil) == nil,
           "visible recovery code hides recovery state when no error is visible")
    expect(AIRequestDiagnostics.visibleErrorRecoverySuggestion(diagnostics: nil,
                                                               errorMessage: "HTTP 401") == "在 AI 设置中重新填写 API Key,并确认供应商账号可用",
           "visible recovery helper can still explain common errors without route diagnostics")
    expect(AIRequestDiagnostics.visibleErrorRecoveryCode(diagnostics: nil,
                                                         errorMessage: "HTTP 401") == "api-key",
           "visible recovery code can still explain common errors without route diagnostics")

    let pending = AIRequestDiagnostics(actionName: "提问",
                                       sourceCharacterCount: 0,
                                       hasImage: false,
                                       fallbackEnabled: true,
                                       routingPreference: .balanced,
                                       candidateCount: 0,
                                       candidateRoutes: [],
                                       candidateUnavailabilitySummary: AIRequestDiagnostics.noCandidateRouteReasonSummary(providers: []),
                                       candidateUnavailabilityRecoverySuggestion: AIRequestDiagnostics.noCandidateRouteRecoverySuggestion(providers: []))
    expect(AIRequestDiagnostics.visibleErrorRecoverySuggestion(diagnostics: pending,
                                                               errorMessage: "没有可用模型") == "在 AI 设置中添加并启用供应商",
           "visible recovery helper exposes missing candidate route recovery")
    expect(AIRequestDiagnostics.visibleErrorRecoveryCode(diagnostics: pending,
                                                         errorMessage: "没有可用模型") == "no-candidate-routes",
           "visible recovery code exposes missing candidate route recovery")

    let waiting = AIRequestDiagnostics(actionName: "提问",
                                       sourceCharacterCount: 0,
                                       hasImage: false,
                                       fallbackEnabled: true,
                                       routingPreference: .balanced,
                                       candidateCount: 1,
                                       candidateRoutes: [route])
    expect(AIRequestDiagnostics.visibleErrorRecoverySuggestion(diagnostics: waiting,
                                                               errorMessage: "等待中") == nil,
           "visible recovery helper suppresses non-actionable pending recovery placeholders")
    expect(AIRequestDiagnostics.visibleErrorRecoveryCode(diagnostics: waiting,
                                                         errorMessage: "等待中") == nil,
           "visible recovery code suppresses non-actionable pending recovery placeholders")

    var succeeded = pending
    succeeded.mark(route: route,
                   status: .succeeded,
                   outputCharacterCount: 12)
    expect(AIRequestDiagnostics.visibleErrorRecoverySuggestion(diagnostics: succeeded,
                                                               errorMessage: "unexpected") == nil,
           "visible recovery helper suppresses successful no-op recovery text")
}

func testAIRequestDiagnosticsClassifiesCommonErrorRecoverySuggestions() {
    expect(AIRequestDiagnostics.recoverySuggestion(forErrorMessage: nil) == nil,
           "common error recovery ignores missing error messages")
    expect(AIRequestDiagnostics.recoveryCode(forErrorMessage: nil) == nil,
           "common error recovery code ignores missing error messages")
    expect(AIRequestDiagnostics.recoveryHint(forErrorMessage: "HTTP 429: rate limit exceeded") == AIRequestRecoveryHint(code: "rate-limit",
                                                                                                                        suggestion: "触发限速;稍后重试、降低频率或切换备用供应商"),
           "common error recovery exposes a stable code and localized suggestion")
    expect(AIRequestDiagnostics.recoverySuggestion(forErrorMessage: "请求失败 (HTTP 401): invalid_api_key") == "在 AI 设置中重新填写 API Key,并确认供应商账号可用",
           "common error recovery identifies API key failures")
    expect(AIRequestDiagnostics.recoveryCode(forErrorMessage: "请求失败 (HTTP 401): invalid_api_key") == "api-key",
           "common error recovery code identifies API key failures")
    expect(AIRequestDiagnostics.recoverySuggestion(forErrorMessage: "没有可用的 AI 供应商,请在设置中启用至少一个供应商。") == "在 AI 设置中添加或启用供应商",
           "common error recovery identifies missing provider configuration")
    expect(AIRequestDiagnostics.recoveryCode(forErrorMessage: "没有可用的 AI 供应商,请在设置中启用至少一个供应商。") == "missing-provider",
           "common error recovery code identifies missing provider configuration")
    expect(AIRequestDiagnostics.recoverySuggestion(forErrorMessage: "未选择可用模型,请在设置中启用或添加模型。") == "在 AI 设置中启用或添加模型,并选择当前模型",
           "common error recovery identifies missing model configuration")
    expect(AIRequestDiagnostics.recoveryCode(forErrorMessage: "未选择可用模型,请在设置中启用或添加模型。") == "missing-model",
           "common error recovery code identifies missing model configuration")
    expect(AIRequestDiagnostics.recoverySuggestion(forErrorMessage: "HTTP 429: rate limit exceeded") == "触发限速;稍后重试、降低频率或切换备用供应商",
           "common error recovery identifies rate limits")
    expect(AIRequestDiagnostics.recoveryCode(forErrorMessage: "HTTP 429: rate limit exceeded") == "rate-limit",
           "common error recovery code identifies rate limits")
    expect(AIRequestDiagnostics.recoverySuggestion(forErrorMessage: "maximum context length exceeded") == "文本超过模型上下文限制;缩短内容或切换长上下文模型",
           "common error recovery identifies context limit failures")
    expect(AIRequestDiagnostics.recoveryCode(forErrorMessage: "maximum context length exceeded") == "context-limit",
           "common error recovery code identifies context limit failures")
    expect(AIRequestDiagnostics.recoverySuggestion(forErrorMessage: "Base URL 无效。") == "检查 Base URL 配置;远程端点请使用 HTTPS",
           "common error recovery identifies endpoint configuration failures")
    expect(AIRequestDiagnostics.recoveryCode(forErrorMessage: "Base URL 无效。") == "base-url",
           "common error recovery code identifies endpoint configuration failures")
    expect(AIRequestDiagnostics.recoverySuggestion(forErrorMessage: "HTTP 404: model not found") == "检查模型名称和 Base URL 是否匹配该供应商",
           "common error recovery identifies model lookup failures")
    expect(AIRequestDiagnostics.recoveryCode(forErrorMessage: "HTTP 404: model not found") == "model-not-found",
           "common error recovery code identifies model lookup failures")
    expect(AIRequestDiagnostics.recoverySuggestion(forErrorMessage: "HTTP 503: service unavailable") == "供应商服务暂时异常;稍后重试或切换备用供应商",
           "common error recovery identifies provider service failures")
    expect(AIRequestDiagnostics.recoveryCode(forErrorMessage: "HTTP 503: service unavailable") == "provider-service",
           "common error recovery code identifies provider service failures")
    expect(AIRequestDiagnostics.recoverySuggestion(forErrorMessage: "The request timed out") == "检查网络、代理和 Base URL 连通性,必要时切换供应商",
           "common error recovery identifies network failures")
    expect(AIRequestDiagnostics.recoveryCode(forErrorMessage: "The request timed out") == "network",
           "common error recovery code identifies network failures")
    expect(AIRequestDiagnostics.recoverySuggestion(forErrorMessage: "unclassified failure") == nil,
           "common error recovery keeps unknown errors available for generic diagnostics")
    expect(AIRequestDiagnostics.recoveryCode(forErrorMessage: "unclassified failure") == nil,
           "common error recovery code keeps unknown errors available for generic diagnostics")
}

func testNoCandidateRouteDiagnosticsExplainProviderReadiness() {
    expect(AIRequestDiagnostics.noCandidateRouteReasonSummary(providers: []) == "no-providers=1",
           "no-candidate route diagnostics report missing providers")
    expect(AIRequestDiagnostics.noCandidateRouteRecoverySuggestion(providers: []) == "在 AI 设置中添加并启用供应商",
           "no-candidate route diagnostics explain how to recover from no providers")

    var disabled = AIProvider(name: "Disabled", apiProtocol: .openAI,
                              baseURL: "https://disabled.test/v1",
                              apiKey: "key",
                              models: [AIModelEntry(name: "gpt-4o-mini")])
    disabled.isEnabled = false
    var missingKey = AIProvider(name: "Missing Key", apiProtocol: .openAI,
                                baseURL: "https://missing-key.test/v1",
                                apiKey: "",
                                models: [AIModelEntry(name: "gpt-4o-mini")])
    missingKey.isEnabled = true
    var noModels = AIProvider(name: "No Models", apiProtocol: .openAI,
                              baseURL: "https://no-models.test/v1",
                              apiKey: "key",
                              models: [AIModelEntry(name: "disabled-model", enabled: false)])
    noModels.isEnabled = true
    var remoteHTTP = AIProvider(name: "Remote HTTP", apiProtocol: .openAI,
                                baseURL: "http://remote.test/v1",
                                apiKey: "key",
                                models: [AIModelEntry(name: "gpt-4o-mini")])
    remoteHTTP.isEnabled = true

    let unavailableProviders = [disabled, missingKey, noModels, remoteHTTP]
    expect(AIRequestDiagnostics.noCandidateRouteReasonSummary(providers: unavailableProviders) == "disabled=1; missing-api-key=1; no-enabled-models=1; remote-http=1",
           "no-candidate route diagnostics summarize provider readiness failures in stable order")
    let recovery = AIRequestDiagnostics.noCandidateRouteRecoverySuggestion(providers: unavailableProviders)
    expect(recovery.contains("disabled=1: 在 AI 设置中启用该供应商"),
           "no-candidate route recovery includes disabled providers")
    expect(recovery.contains("missing-api-key=1: 在 AI 设置中重新填写 API Key"),
           "no-candidate route recovery includes missing API keys")
    expect(recovery.contains("no-enabled-models=1: 在 AI 设置中启用至少一个模型"),
           "no-candidate route recovery includes disabled model lists")
    expect(recovery.contains("remote-http=1: 远程端点请改用 HTTPS;HTTP 仅允许 localhost"),
           "no-candidate route recovery includes remote HTTP endpoints")

    var localNoModels = AIProvider.preset(.ollama)
    localNoModels.models = [AIModelEntry(name: "llama3.1", enabled: false)]
    expect(AIRequestDiagnostics.noCandidateRouteRecoverySuggestion(providers: [localNoModels]).contains("ollama pull llama3.1"),
           "no-candidate route recovery gives local model setup guidance for Ollama")

    var ready = AIProvider(name: "Ready", apiProtocol: .openAI,
                           baseURL: "https://ready.test/v1",
                           apiKey: "key",
                           models: [AIModelEntry(name: "gpt-4o-mini")])
    ready.isEnabled = true
    expect(AIRequestDiagnostics.noCandidateRouteReasonSummary(providers: [ready]) == "ready-providers=1; no-selected-route=1",
           "no-candidate route diagnostics distinguish ready providers from missing selected routes")
    expect(AIRequestDiagnostics.noCandidateRouteRecoverySuggestion(providers: [ready]) == "在 AI 设置中选择当前模型,或开启自动路由/fallback",
           "no-candidate route recovery explains how to use existing ready providers")
}

func testAIRequestAttemptDiagnosticFormatsDurations() {
    expect(AIRequestAttemptDiagnostic.formattedDuration(milliseconds: -5) == "0ms",
           "attempt diagnostics clamps negative durations")
    expect(AIRequestAttemptDiagnostic.formattedDuration(milliseconds: 999) == "999ms",
           "attempt diagnostics keeps subsecond durations in milliseconds")
    expect(AIRequestAttemptDiagnostic.formattedDuration(milliseconds: 1_250) == "1.2s",
           "attempt diagnostics formats short seconds with one decimal")
    expect(AIRequestAttemptDiagnostic.formattedDuration(milliseconds: 12_400) == "12s",
           "attempt diagnostics rounds long seconds")

    let start = Date(timeIntervalSince1970: 100)
    let now = Date(timeIntervalSince1970: 101.234)
    expect(AIRequestAttemptDiagnostic.elapsedMilliseconds(since: start, now: now) == 1_234,
           "attempt diagnostics computes elapsed milliseconds")

    let route = AIRequestRoute(providerID: "p1",
                               providerName: "Primary",
                               modelName: "fast-model",
                               reason: "当前模型")
    let line = AIRequestAttemptDiagnostic(route: route,
                                          status: .failed,
                                          message: nil,
                                          outputCharacterCount: -3).summaryLine
    expect(line.contains("输出 0 字"),
           "attempt diagnostics clamps negative output character counts")
}

func testSensitiveTextSanitizerRedactsSensitiveErrorFragments() {
    let slackToken = "xoxb-" + "123456789012-" + "abcdefghijklmnopqrstuvwxyz"
    let message = """
    HTTP 401 {"error":"bad key","api_key":"sk-abcdefghijklmnopqrstuvwxyz","token":"super-secret-token-value"}
    Authorization: Bearer sk-live-secret-value-1234567890 password=plainsecret123
    Authorization: Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ== x-api-key: provider-secret-key
    https://example.test/callback?access_token=visible-access-token&api_key=query-api-key-value&client_secret=query-client-secret-value&ok=true
    github ghp_abcdefghijklmnopqrstuvwxyz123456 github_pat_abcdefghijklmnopqrstuvwxyz1234567890
    slack \(slackToken)
    aws AKIA1234567890ABCDEF google AIzaabcdefghijklmnopqrstuvwxyz1234567890
    jwt eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.VerySecretSignatureValue1234567890
    failed at /Users/alice/Projects/SnapAI/build.log and /Users/bob/Library/Logs/snapai.log
    """
    let sanitized = SensitiveTextSanitizer.sanitizedMessage(message, limit: 1_000)
    expect(sanitized.contains("[REDACTED"), "redacts sensitive fragments")
    expect(!sanitized.contains("sk-abcdefghijklmnopqrstuvwxyz"), "redacts json api key")
    expect(!sanitized.contains("super-secret-token-value"), "redacts json token")
    expect(!sanitized.contains("sk-live-secret-value-1234567890"), "redacts bearer secret")
    expect(!sanitized.contains("plainsecret123"), "redacts plain password field")
    expect(!sanitized.contains("QWxhZGRpbjpvcGVuIHNlc2FtZQ=="), "redacts basic authorization secret")
    expect(!sanitized.contains("provider-secret-key"), "redacts x-api-key header")
    expect(!sanitized.contains("visible-access-token"), "redacts access token query parameter")
    expect(!sanitized.contains("query-api-key-value"), "redacts api key query parameter")
    expect(!sanitized.contains("query-client-secret-value"), "redacts client secret query parameter")
    expect(sanitized.contains("ok=true"), "keeps unrelated query parameters")
    expect(!sanitized.contains("ghp_abcdefghijklmnopqrstuvwxyz123456"), "redacts GitHub classic tokens")
    expect(!sanitized.contains("github_pat_abcdefghijklmnopqrstuvwxyz1234567890"), "redacts GitHub fine-grained tokens")
    expect(!sanitized.contains(slackToken), "redacts Slack bot tokens")
    expect(!sanitized.contains("AKIA1234567890ABCDEF"), "redacts AWS access key ids")
    expect(!sanitized.contains("AIzaabcdefghijklmnopqrstuvwxyz1234567890"), "redacts Google API keys")
    expect(!sanitized.contains("VerySecretSignatureValue1234567890"), "redacts JWT values")
    expect(!sanitized.contains("/Users/alice"), "redacts user directory paths in sanitized messages")
    expect(!sanitized.contains("/Users/bob"), "redacts multiple user directory paths in sanitized messages")
    expect(sanitized.contains("/Users/[user]/Projects/SnapAI/build.log"), "keeps useful path suffix after user redaction")
    expect(!sanitized.contains("\n"), "flattens multi-line error messages")

    let redactedPath = SensitiveTextSanitizer.redactedLocalPaths("open /Users/alice/Applications/SnapAI.app",
                                                                 homeDirectory: "/Users/alice")
    expect(redactedPath == "open ~/Applications/SnapAI.app",
           "redacted local paths collapse the current home directory")
    let otherUserPath = SensitiveTextSanitizer.redactedLocalPaths("open /Users/bob/Applications/SnapAI.app",
                                                                  homeDirectory: "/Users/alice")
    expect(otherUserPath == "open /Users/[user]/Applications/SnapAI.app",
           "redacted local paths hide other user directory names")
    let diagnosticText = SensitiveTextSanitizer.sanitizedDiagnosticText("""
    route failed
    Authorization: Bearer sk-live-secret-value-1234567890
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAASecretPrivateKeyBody
    -----END OPENSSH PRIVATE KEY-----
    log: /Users/alice/Library/Logs/snapai.log
    """)
    expect(diagnosticText.contains("\n"), "diagnostic sanitizer preserves useful line breaks")
    expect(!diagnosticText.contains("sk-live-secret-value-1234567890"), "diagnostic sanitizer redacts secrets")
    expect(!diagnosticText.contains("SecretPrivateKeyBody"), "diagnostic sanitizer redacts PEM private key bodies")
    expect(diagnosticText.contains("[REDACTED_PRIVATE_KEY]"), "diagnostic sanitizer keeps a private-key redaction marker")
    expect(!diagnosticText.contains("/Users/alice"), "diagnostic sanitizer redacts user paths")

    let long = SensitiveTextSanitizer.sanitizedMessage(String(repeating: "错误详情", count: 80))
    expect(long.contains("..."), "truncates long sanitized messages")
}

func testAIRequestDiagnosticsUsesSensitiveTextSanitizer() {
    let route = AIRequestRoute(providerID: "p1",
                               providerName: "Primary",
                               modelName: "fast-model",
                               reason: "当前模型")
    let line = AIRequestAttemptDiagnostic(route: route,
                                          status: .failed,
                                          message: #"Authorization: Bearer sk-live-secret-value-1234567890"#).summaryLine
    expect(line.contains("[REDACTED"), "AI request diagnostics redacts sensitive fragments")
    expect(!line.contains("sk-live-secret-value-1234567890"), "AI request diagnostics omits bearer secret")
}

func testAIRequestDiagnosticsSanitizesRouteMetadata() {
    let route = AIRequestRoute(providerID: "p1",
                               providerName: "Primary\n# 注入|`Provider`",
                               modelName: "fast-model sk-live-secret-value-1234567890",
                               reason: "备用\n原因|`R`")
    var diagnostics = AIRequestDiagnostics(actionName: "润色\n# 注入|`Action`",
                                           sourceCharacterCount: 1,
                                           hasImage: false,
                                           fallbackEnabled: true,
                                           routingPreference: .balanced,
                                           candidateCount: 1,
                                           candidateRoutes: [route])
    diagnostics.mark(route: route,
                     status: .failed,
                     message: "Authorization: Bearer sk-live-secret-value-1234567890")

    let summary = diagnostics.summaryText
    expect(summary.contains("Action: 润色 # 注入/'Action'"),
           "request diagnostics keeps unsafe action names single-line")
    expect(summary.contains("Primary # 注入/'Provider' / fast-model [REDACTED_KEY] - 备用 原因/'R'"),
           "request diagnostics keeps route metadata single-line and redacted")
    expect(summary.contains("Primary # 注入/'Provider' / fast-model [REDACTED_KEY] (备用 原因/'R') -> 失败"),
           "request attempt diagnostics uses sanitized route metadata")
    expect(!summary.contains("润色\n# 注入"), "request diagnostics does not allow action newline injection")
    expect(!summary.contains("Primary\n# 注入"), "request diagnostics does not allow provider newline injection")
    expect(!summary.contains("备用\n原因"), "request diagnostics does not allow reason newline injection")
    expect(!summary.contains("|`"), "request diagnostics removes markdown-sensitive metadata characters")
    expect(!summary.contains("sk-live-secret-value-1234567890"),
           "request diagnostics does not leak key-like route metadata or error messages")
}

func testAIRequestRouteDisplayNotesAreSanitized() {
    let route = AIRequestRoute(providerID: "p1",
                               providerName: "Primary\n# 注入|`Provider`",
                               modelName: "fast-model sk-live-secret-value-1234567890",
                               reason: "备用\n原因|`R`")
    expect(route.displayRouteNote == "备用 原因/'R'",
           "route display note sanitizes route reason")
    expect(route.fallbackSwitchNote.contains("Primary # 注入/'Provider' / fast-model [REDACTED_KEY] 失败"),
           "fallback switch note sanitizes provider and model metadata")
    expect(!route.fallbackSwitchNote.contains("\n"),
           "fallback switch note keeps UI text single-line")
    expect(!route.fallbackSwitchNote.contains("sk-live-secret-value-1234567890"),
           "fallback switch note redacts secrets")
    expect(!route.fallbackSwitchNote.contains("|`"),
           "fallback switch note removes markdown-sensitive metadata")

    let diagnostics = AIRequestDiagnostics(actionName: "润色",
                                           sourceCharacterCount: 1,
                                           hasImage: true,
                                           fallbackEnabled: true,
                                           routingPreference: .balanced,
                                           candidateCount: 1,
                                           payload: AIRequestPayloadDiagnostic(messageCount: 1,
                                                                               textCharacterCount: 36_000,
                                                                               estimatedTextTokens: 9_000,
                                                                               imageAttachmentCount: 1),
                                           candidateRoutes: [route])
    let skipNote = diagnostics.routeSkipSwitchNote(for: route, nextRoute: route)
    expect(skipNote.contains("Primary # 注入/'Provider' / fast-model [REDACTED_KEY]"),
           "skip switch note sanitizes provider and model metadata")
    expect(!skipNote.contains("\n"),
           "skip switch note keeps UI text single-line")
    expect(!skipNote.contains("sk-live-secret-value-1234567890"),
           "skip switch note redacts secrets")
    expect(!skipNote.contains("|`"),
           "skip switch note removes markdown-sensitive metadata")

    let safeFallback = AIRequestRoute(providerID: "p2",
                                      providerName: "Fallback",
                                      modelName: "gpt-4o-mini",
                                      reason: "备用模型")
    let preflightDiagnostics = AIRequestDiagnostics(actionName: "润色",
                                                    sourceCharacterCount: 1,
                                                    hasImage: true,
                                                    fallbackEnabled: true,
                                                    autoRouteEnabled: true,
                                                    routingPreference: .balanced,
                                                    candidateCount: 2,
                                                    payload: AIRequestPayloadDiagnostic(messageCount: 1,
                                                                                        textCharacterCount: 36_000,
                                                                                        estimatedTextTokens: 9_000,
                                                                                        imageAttachmentCount: 1),
                                                    candidateRoutes: [route, safeFallback])
    let preflightSummary = preflightDiagnostics.preflightSkippedRouteSummary
    expect(preflightSummary.contains("Primary # 注入/'Provider' / fast-model [REDACTED_KEY]"),
           "preflight skip summary sanitizes provider and model metadata")
    expect(!preflightSummary.contains("\n"),
           "preflight skip summary keeps UI text single-line")
    expect(!preflightSummary.contains("sk-live-secret-value-1234567890"),
           "preflight skip summary redacts secrets")
    expect(!preflightSummary.contains("|`"),
           "preflight skip summary removes markdown-sensitive metadata")
}

func testAIRouterSkipsDisabledActionOverrideModel() {
    let settings = AppSettings()
    var provider = AIProvider(name: "Primary", apiProtocol: .openAI,
                              baseURL: "https://primary.test/v1",
                              apiKey: "key",
                              models: [
                                AIModelEntry(name: "disabled-model", enabled: false),
                                AIModelEntry(name: "enabled-model", enabled: true)
                              ])
    provider.isEnabled = true
    settings.providers = [provider]
    settings.activeProviderID = provider.id
    settings.activeModel = "enabled-model"
    settings.autoRouteEnabled = false
    settings.fallbackEnabled = false

    var action = AIAction.defaults()[0]
    action.providerID = provider.id
    action.modelOverride = "disabled-model"

    let routes = AIRequestRouter.candidates(settings: settings,
                                            action: action,
                                            sourceText: "hello",
                                            hasImage: false)
    expect(routes.first?.modelName == "enabled-model", "skips disabled action override model")
}

func testAIRouterSkipsDisabledActiveModel() {
    let settings = AppSettings()
    var provider = AIProvider(name: "Primary", apiProtocol: .openAI,
                              baseURL: "https://primary.test/v1",
                              apiKey: "key",
                              models: [
                                AIModelEntry(name: "disabled-active", enabled: false),
                                AIModelEntry(name: "enabled-model", enabled: true)
                              ])
    provider.isEnabled = true
    settings.providers = [provider]
    settings.activeProviderID = provider.id
    settings.activeModel = "disabled-active"
    settings.autoRouteEnabled = false
    settings.fallbackEnabled = false

    let routes = AIRequestRouter.candidates(settings: settings,
                                            action: AIAction.defaults()[0],
                                            sourceText: "hello",
                                            hasImage: false)
    expect(settings.model == "enabled-model", "settings.model falls back to first enabled model")
    expect(settings.modelSelectionTitle == "enabled-model", "model selector title uses safe model")
    expect(routes.map(\.modelName) == ["enabled-model"], "router does not emit disabled active model")
    expect(routes.first?.reason == "当前可用模型", "router explains active model fallback")
}

func testAIRouterScopedSettingsRequiresEnabledRouteModel() {
    let settings = AppSettings()
    var provider = AIProvider(name: "Primary", apiProtocol: .openAI,
                              baseURL: "https://primary.test/v1",
                              apiKey: "key",
                              models: [
                                AIModelEntry(name: "enabled-model", enabled: true),
                                AIModelEntry(name: "disabled-model", enabled: false)
                              ])
    provider.id = "primary"
    provider.isEnabled = true
    settings.providers = [provider]
    settings.activeProviderID = provider.id
    settings.activeModel = "enabled-model"

    let enabledRoute = AIRequestRoute(providerID: provider.id,
                                      providerName: provider.name,
                                      modelName: "enabled-model",
                                      reason: "测试")
    let enabledScoped = AIRequestRouter.scopedSettings(from: settings, route: enabledRoute)
    expect(enabledScoped?.activeProviderID == provider.id,
           "scoped router settings preserve the route provider")
    expect(enabledScoped?.model == "enabled-model",
           "scoped router settings use the requested enabled route model")

    let disabledRoute = AIRequestRoute(providerID: provider.id,
                                       providerName: provider.name,
                                       modelName: "disabled-model",
                                       reason: "测试")
    expect(AIRequestRouter.scopedSettings(from: settings, route: disabledRoute) == nil,
           "scoped router settings reject disabled route models instead of falling back silently")

    let unknownRoute = AIRequestRoute(providerID: provider.id,
                                      providerName: provider.name,
                                      modelName: "missing-model",
                                      reason: "测试")
    expect(AIRequestRouter.scopedSettings(from: settings, route: unknownRoute) == nil,
           "scoped router settings reject unknown route models instead of falling back silently")

    provider.isEnabled = false
    settings.providers = [provider]
    expect(AIRequestRouter.scopedSettings(from: settings, route: enabledRoute) == nil,
           "scoped router settings reject disabled route providers")
}

func testAIRouterProviderRequestReadiness() {
    var ready = AIProvider(name: "Ready", apiProtocol: .openAI,
                           baseURL: "api.openai.com",
                           apiKey: "key",
                           models: [AIModelEntry(name: "gpt-4o-mini")])
    ready.isEnabled = true
    expect(AIRequestRouter.isProviderRequestReady(ready),
           "provider readiness accepts enabled providers with key, host-only HTTPS base URL, and enabled models")
    expect(AIRequestRouter.providerReadiness(ready) == .ready,
           "provider readiness reports ready providers")
    expect(AIRequestRouter.providerReadiness(ready).recoverySuggestion == "无需处理",
           "provider readiness explains that ready providers need no recovery")

    var localHTTP = ready
    localHTTP.baseURL = "http://localhost:11434"
    localHTTP.apiKey = "ollama"
    expect(AIRequestRouter.isProviderRequestReady(localHTTP),
           "provider readiness accepts local HTTP providers")
    expect(AIRequestRouter.providerReadiness(localHTTP) == .ready,
           "provider readiness reports local HTTP providers as ready")

    var remoteHTTP = ready
    remoteHTTP.baseURL = "http://api.example.test/v1"
    expect(!AIRequestRouter.isProviderRequestReady(remoteHTTP),
           "provider readiness rejects non-local HTTP providers")
    expect(AIRequestRouter.providerReadiness(remoteHTTP) == .remoteHTTP,
           "provider readiness explains remote HTTP rejection")
    expect(AIRequestRouter.providerReadiness(remoteHTTP).recoverySuggestion.contains("HTTPS"),
           "provider readiness suggests HTTPS for remote HTTP endpoints")

    var blankKey = ready
    blankKey.apiKey = " \n "
    expect(!AIRequestRouter.isProviderRequestReady(blankKey),
           "provider readiness rejects missing API keys")
    expect(AIRequestRouter.providerReadiness(blankKey) == .missingAPIKey,
           "provider readiness explains missing API keys")
    expect(AIRequestRouter.providerReadiness(blankKey).recoverySuggestion.contains("API Key"),
           "provider readiness suggests refilling missing API keys")

    var blankURL = ready
    blankURL.baseURL = " "
    expect(!AIRequestRouter.isProviderRequestReady(blankURL),
           "provider readiness rejects missing base URLs")
    expect(AIRequestRouter.providerReadiness(blankURL) == .invalidBaseURL,
           "provider readiness explains invalid base URLs")
    expect(AIRequestRouter.providerReadiness(blankURL).recoverySuggestion.contains("Base URL"),
           "provider readiness suggests checking invalid base URLs")

    var noEnabledModels = ready
    noEnabledModels.models = [AIModelEntry(name: "disabled-model", enabled: false)]
    expect(!AIRequestRouter.isProviderRequestReady(noEnabledModels),
           "provider readiness rejects providers without enabled models")
    expect(AIRequestRouter.providerReadiness(noEnabledModels) == .noEnabledModels,
           "provider readiness explains missing enabled models")
    expect(AIRequestRouter.providerReadiness(noEnabledModels).recoverySuggestion.contains("启用至少一个模型"),
           "provider readiness suggests enabling at least one model")

    ready.isEnabled = false
    expect(!AIRequestRouter.isProviderRequestReady(ready),
           "provider readiness rejects disabled providers")
    expect(AIRequestRouter.providerReadiness(ready) == .disabled,
           "provider readiness explains disabled providers")
    expect(AIRequestRouter.providerReadiness(ready).recoverySuggestion.contains("启用该供应商"),
           "provider readiness suggests enabling disabled providers")

    let ollama = AIProvider.preset(.ollama)
    let lmStudio = AIProvider.preset(.lmStudio)
    expect(ollama.isLocalEndpoint, "Ollama preset is recognized as a local endpoint")
    expect(lmStudio.isLocalEndpoint, "LM Studio preset is recognized as a local endpoint")
    expect(!AIProvider.preset(.openAI).isLocalEndpoint, "OpenAI preset is not treated as local")
    expect(LocalModelHealth.make(provider: ollama)?.serviceKind == .ollama,
           "local model health recognizes Ollama providers")
    expect(LocalModelHealth.make(provider: lmStudio)?.serviceKind == .lmStudio,
           "local model health recognizes LM Studio providers")

    var localMissingKey = AIProvider.preset(.lmStudio)
    localMissingKey.apiKey = ""
    localMissingKey.models = [AIModelEntry(name: "local-chat")]
    expect(AIRequestRouter.providerReadiness(localMissingKey) == .missingAPIKey,
           "local providers still require an API key placeholder for the current client")
    expect(AIRequestRouter.providerRecoverySuggestion(localMissingKey).contains("lm-studio"),
           "local provider recovery suggests an LM Studio placeholder API key")

    var localNoModels = AIProvider.preset(.ollama)
    localNoModels.models = [AIModelEntry(name: "llama3.1", enabled: false)]
    expect(AIRequestRouter.providerReadiness(localNoModels) == .noEnabledModels,
           "local providers without enabled models report no-enabled-models")
    expect(AIRequestRouter.providerRecoverySuggestion(localNoModels).contains("ollama pull llama3.1"),
           "local provider recovery explains how to prepare Ollama models")
}

func testAIRouterFallbackSkipsProvidersThatCannotRequest() {
    let settings = AppSettings()
    var primary = AIProvider(name: "Primary", apiProtocol: .openAI,
                             baseURL: "https://primary.test/v1",
                             apiKey: "key",
                             models: [AIModelEntry(name: "primary-model")])
    primary.id = "primary"
    primary.isEnabled = true

    var noKey = AIProvider(name: "NoKey", apiProtocol: .openAI,
                           baseURL: "https://nokey.test/v1",
                           apiKey: "",
                           models: [AIModelEntry(name: "no-key-model")])
    noKey.id = "no-key"
    noKey.isEnabled = true

    var blankURL = AIProvider(name: "BlankURL", apiProtocol: .openAI,
                              baseURL: "",
                              apiKey: "key",
                              models: [AIModelEntry(name: "blank-url-model")])
    blankURL.id = "blank-url"
    blankURL.isEnabled = true

    var remoteHTTP = AIProvider(name: "RemoteHTTP", apiProtocol: .openAI,
                                baseURL: "http://remote.example.test/v1",
                                apiKey: "key",
                                models: [AIModelEntry(name: "remote-http-model")])
    remoteHTTP.id = "remote-http"
    remoteHTTP.isEnabled = true

    var disabledModel = AIProvider(name: "DisabledModel", apiProtocol: .openAI,
                                   baseURL: "https://disabled-model.test/v1",
                                   apiKey: "key",
                                   models: [AIModelEntry(name: "disabled-model", enabled: false)])
    disabledModel.id = "disabled-model"
    disabledModel.isEnabled = true

    var readyFallback = AIProvider(name: "ReadyFallback", apiProtocol: .openAI,
                                   baseURL: "https://fallback.test/v1",
                                   apiKey: "key",
                                   models: [AIModelEntry(name: "ready-fallback-model")])
    readyFallback.id = "ready-fallback"
    readyFallback.isEnabled = true

    settings.providers = [primary, noKey, blankURL, remoteHTTP, disabledModel, readyFallback]
    settings.activeProviderID = primary.id
    settings.activeModel = "primary-model"
    settings.autoRouteEnabled = false
    settings.fallbackEnabled = true

    let routes = AIRequestRouter.candidates(settings: settings,
                                            action: AIAction.defaults()[0],
                                            sourceText: "hello",
                                            hasImage: false)
    expect(routes.map(\.providerID) == ["primary", "ready-fallback"],
           "fallback routes skip providers that cannot make a request")
    expect(!routes.contains { $0.providerID == noKey.id },
           "fallback routes omit missing-key providers")
    expect(!routes.contains { $0.providerID == blankURL.id },
           "fallback routes omit missing-base-url providers")
    expect(!routes.contains { $0.providerID == remoteHTTP.id },
           "fallback routes omit insecure remote HTTP providers")
    expect(!routes.contains { $0.providerID == disabledModel.id },
           "fallback routes omit providers without enabled models")
}

func testAIRouterKeepsActiveProviderWhenNotRequestReady() {
    let settings = AppSettings()
    var primary = AIProvider(name: "Primary", apiProtocol: .openAI,
                             baseURL: "https://primary.test/v1",
                             apiKey: "",
                             models: [AIModelEntry(name: "primary-model")])
    primary.id = "primary"
    primary.isEnabled = true
    var fallback = AIProvider(name: "Fallback", apiProtocol: .openAI,
                              baseURL: "https://fallback.test/v1",
                              apiKey: "key",
                              models: [AIModelEntry(name: "fallback-model")])
    fallback.id = "fallback"
    fallback.isEnabled = true

    settings.providers = [primary, fallback]
    settings.activeProviderID = primary.id
    settings.activeModel = "primary-model"
    settings.autoRouteEnabled = false
    settings.fallbackEnabled = true

    let routes = AIRequestRouter.candidates(settings: settings,
                                            action: AIAction.defaults()[0],
                                            sourceText: "hello",
                                            hasImage: false)
    expect(routes.map(\.providerID) == ["primary", "fallback"],
           "router keeps the active provider first so missing-key errors stay actionable, then adds ready fallback routes")
}

func testSettingsModelClearsWhenActiveProviderHasNoEnabledModels() {
    let settings = AppSettings()
    var provider = AIProvider(name: "Primary", apiProtocol: .openAI,
                              baseURL: "https://primary.test/v1",
                              apiKey: "key",
                              models: [AIModelEntry(name: "disabled-model", enabled: false)])
    provider.isEnabled = true
    settings.providers = [provider]
    settings.activeProviderID = provider.id
    settings.activeModel = "disabled-model"

    expect(settings.model.isEmpty, "settings.model is empty when active provider has no enabled models")
    expect(settings.modelSelectionTitle == "选择模型", "model selector title explains missing enabled model")
}

func testPermissionDiagnosticsUsesSafeActiveModelSummary() {
    let settings = AppSettings()
    var provider = AIProvider(name: "Primary", apiProtocol: .openAI,
                              baseURL: "https://primary.test/v1",
                              apiKey: "key",
                              models: [
                                AIModelEntry(name: "disabled-active", enabled: false),
                                AIModelEntry(name: "enabled-model", enabled: true)
                              ])
    provider.isEnabled = true
    settings.providers = [provider]
    settings.activeProviderID = provider.id
    settings.activeModel = "disabled-active"

    expect(PermissionHealthSnapshot.activeModelSummary(settings: settings) == "Primary / enabled-model",
           "permission diagnostics reports the safe active model")

    var unsafeProvider = provider
    unsafeProvider.name = "Primary\napi_key=sk-live-secret-value-1234567890 / /Users/alice/project"
    unsafeProvider.models = [AIModelEntry(name: "enabled-model\n/Users/alice/model", enabled: true)]
    settings.providers = [unsafeProvider]
    settings.activeProviderID = unsafeProvider.id
    settings.activeModel = "enabled-model\n/Users/alice/model"
    let unsafeSummary = PermissionHealthSnapshot.activeModelSummary(settings: settings)
    expect(!unsafeSummary.contains("sk-live-secret-value-1234567890"),
           "active model summary redacts secrets from provider names")
    expect(!unsafeSummary.contains("/Users/alice"),
           "active model summary redacts local paths from provider and model names")
    expect(!unsafeSummary.contains("\n"),
           "active model summary is single-line")
    expect(unsafeSummary.contains("[REDACTED]"),
           "active model summary keeps a redaction marker for sensitive fragments")
}

func testModelCapabilityInference() {
    let gemini = ModelCapabilityRegistry.capability(for: "gemini-1.5-pro-1m")
    expect(gemini.supportsVision, "gemini supports vision")
    expect(gemini.supportsLongContext, "gemini 1m supports long context")

    let r1 = ModelCapabilityRegistry.capability(for: "deepseek-r1")
    expect(r1.supportsReasoning, "r1 supports reasoning")
    expect(r1.isCodeCapable, "deepseek is code capable")

    let mini = ModelCapabilityRegistry.capability(for: "gpt-4o-mini")
    expect(mini.isFast, "mini model is fast")
    expect(mini.isEconomical, "mini model is economical")
}

func testAIRouterUsesCapabilityReasonForCodeAction() {
    let settings = AppSettings()
    var provider = AIProvider(name: "Primary", apiProtocol: .openAI,
                              baseURL: "https://primary.test/v1",
                              apiKey: "key",
                              models: [
                                AIModelEntry(name: "gpt-4o-mini"),
                                AIModelEntry(name: "deepseek-coder")
                              ])
    provider.isEnabled = true
    settings.providers = [provider]
    settings.activeProviderID = provider.id
    settings.activeModel = "gpt-4o-mini"
    settings.autoRouteEnabled = true
    settings.fallbackEnabled = false

    var action = AIAction.defaults()[4]
    action.providerID = nil

    let routes = AIRequestRouter.candidates(settings: settings,
                                            action: action,
                                            sourceText: "func test() {}",
                                            hasImage: false)
    expect(routes.first?.reason == "当前模型", "keeps current model as explicit first route")
    expect(routes.contains { $0.reason == "代码任务优先" }, "adds code capability route reason")
}

func testAIRouterUsesFullRequestSizeForLongContextRouting() {
    expect(AIRequestRouter.routingTextLength(sourceText: "short",
                                             routingTextCharacterCount: nil) == 5,
           "router falls back to source text length when no payload size is provided")
    expect(AIRequestRouter.routingTextLength(sourceText: "short",
                                             routingTextCharacterCount: 12_000) == 12_000,
           "router can use full request payload size for routing")
    expect(AIRequestRouter.routingTextLength(sourceText: "short",
                                             routingTextCharacterCount: -5) == 0,
           "router clamps invalid payload sizes")

    let settings = AppSettings()
    var provider = AIProvider(name: "Primary", apiProtocol: .openAI,
                              baseURL: "https://primary.test/v1",
                              apiKey: "key",
                              models: [
                                AIModelEntry(name: "local-small"),
                                AIModelEntry(name: "claude-sonnet-200k")
                              ])
    provider.isEnabled = true
    settings.providers = [provider]
    settings.activeProviderID = provider.id
    settings.activeModel = "local-small"
    settings.autoRouteEnabled = true
    settings.fallbackEnabled = false

    let shortRoutes = AIRequestRouter.candidates(settings: settings,
                                                 action: AIAction.defaults()[0],
                                                 sourceText: "short",
                                                 hasImage: false)
    expect(shortRoutes.contains { $0.modelName == "claude-sonnet-200k" && $0.reason == "备用模型" },
           "short source text alone does not trigger long-context routing")

    let longPayloadRoutes = AIRequestRouter.candidates(settings: settings,
                                                       action: AIAction.defaults()[0],
                                                       sourceText: "short",
                                                       hasImage: false,
                                                       routingTextCharacterCount: 12_000)
    expect(longPayloadRoutes.contains { $0.modelName == "claude-sonnet-200k" && $0.reason == "长文本优先" },
           "full request payload size can trigger long-context routing even when source text is short")
}

func testAIRouterDemotesOverLimitModelsWhenAutoRouting() {
    let settings = AppSettings()
    var provider = AIProvider(name: "Primary", apiProtocol: .openAI,
                              baseURL: "https://primary.test/v1",
                              apiKey: "key",
                              models: [
                                AIModelEntry(name: "tiny-8k"),
                                AIModelEntry(name: "claude-sonnet-200k")
                              ])
    provider.isEnabled = true
    settings.providers = [provider]
    settings.activeProviderID = provider.id
    settings.activeModel = "tiny-8k"
    settings.autoRouteEnabled = true
    settings.fallbackEnabled = false

    expect(AIRequestRouter.contextFitStatus(modelName: "tiny-8k",
                                            providerName: "Primary",
                                            textLength: 40_000) == "over-limit",
           "router can detect over-limit model candidates")
    expect(AIRequestRouter.contextFitStatus(modelName: "claude-sonnet-200k",
                                            providerName: "Primary",
                                            textLength: 40_000) == "ok",
           "router can detect fitting long-context model candidates")

    let autoRoutes = AIRequestRouter.candidates(settings: settings,
                                                action: AIAction.defaults()[0],
                                                sourceText: "short",
                                                hasImage: false,
                                                routingTextCharacterCount: 40_000)
    expect(autoRoutes.first?.modelName == "claude-sonnet-200k",
           "auto routing promotes a fitting long-context model ahead of an over-limit active model")
    expect(autoRoutes.first?.reason == "长文本优先",
           "auto routing explains long-context promotion")
    expect(autoRoutes.dropFirst().contains { $0.modelName == "tiny-8k" },
           "auto routing keeps over-limit models as later fallback candidates")

    settings.autoRouteEnabled = false
    settings.fallbackEnabled = false
    let manualRoutes = AIRequestRouter.candidates(settings: settings,
                                                  action: AIAction.defaults()[0],
                                                  sourceText: "short",
                                                  hasImage: false,
                                                  routingTextCharacterCount: 40_000)
    expect(manualRoutes.first?.modelName == "tiny-8k",
           "manual routing still honors the selected current model")
}

func testAIRouterPromotesVisionModelForImageRequests() {
    let settings = AppSettings()
    var provider = AIProvider(name: "Primary", apiProtocol: .openAI,
                              baseURL: "https://primary.test/v1",
                              apiKey: "key",
                              models: [
                                AIModelEntry(name: "text-small"),
                                AIModelEntry(name: "gpt-4o-mini")
                              ])
    provider.isEnabled = true
    settings.providers = [provider]
    settings.activeProviderID = provider.id
    settings.activeModel = "text-small"
    settings.autoRouteEnabled = true
    settings.fallbackEnabled = false

    expect(!AIRequestRouter.modelSupportsImageInput(modelName: "text-small",
                                                    providerName: "Primary"),
           "router can detect text-only model candidates")
    expect(AIRequestRouter.modelSupportsImageInput(modelName: "gpt-4o-mini",
                                                   providerName: "Primary"),
           "router can detect vision-capable model candidates")

    let imageRoutes = AIRequestRouter.candidates(settings: settings,
                                                 action: AIAction.defaults()[0],
                                                 sourceText: "describe this image",
                                                 hasImage: true)
    expect(imageRoutes.first?.modelName == "gpt-4o-mini",
           "auto routing promotes a vision model ahead of a text-only active model for image requests")
    expect(imageRoutes.first?.reason == "图片输入优先",
           "auto routing explains vision promotion")
    expect(imageRoutes.dropFirst().contains { $0.modelName == "text-small" },
           "auto routing keeps text-only models as later fallback candidates")

    settings.autoRouteEnabled = false
    settings.fallbackEnabled = false
    let manualRoutes = AIRequestRouter.candidates(settings: settings,
                                                  action: AIAction.defaults()[0],
                                                  sourceText: "describe this image",
                                                  hasImage: true)
    expect(manualRoutes.first?.modelName == "text-small",
           "manual routing still honors the selected text-only model for image requests")
}

func testAIRouterPromotesReasoningModelForThinkingActions() {
    let settings = AppSettings()
    var provider = AIProvider(name: "Primary", apiProtocol: .openAI,
                              baseURL: "https://primary.test/v1",
                              apiKey: "key",
                              models: [
                                AIModelEntry(name: "fast-chat"),
                                AIModelEntry(name: "deepseek-r1")
                              ])
    provider.isEnabled = true
    settings.providers = [provider]
    settings.activeProviderID = provider.id
    settings.activeModel = "fast-chat"
    settings.autoRouteEnabled = true
    settings.fallbackEnabled = false

    var action = AIAction.defaults()[0]
    action.thinkingMode = true

    expect(!AIRequestRouter.modelSupportsReasoning(modelName: "fast-chat",
                                                   providerName: "Primary"),
           "router can detect non-reasoning model candidates")
    expect(AIRequestRouter.modelSupportsReasoning(modelName: "deepseek-r1",
                                                  providerName: "Primary"),
           "router can detect reasoning-capable model candidates")

    let autoRoutes = AIRequestRouter.candidates(settings: settings,
                                                action: action,
                                                sourceText: "需要多步分析的问题",
                                                hasImage: false)
    expect(autoRoutes.first?.modelName == "deepseek-r1",
           "auto routing promotes a reasoning model ahead of a non-reasoning active model for thinking actions")
    expect(autoRoutes.first?.reason == "推理任务优先",
           "auto routing explains reasoning promotion")
    expect(autoRoutes.dropFirst().contains { $0.modelName == "fast-chat" },
           "auto routing keeps non-reasoning models as later fallback candidates")

    settings.autoRouteEnabled = false
    settings.fallbackEnabled = false
    let manualRoutes = AIRequestRouter.candidates(settings: settings,
                                                  action: action,
                                                  sourceText: "需要多步分析的问题",
                                                  hasImage: false)
    expect(manualRoutes.first?.modelName == "fast-chat",
           "manual routing still honors the selected non-reasoning model for thinking actions")
}

func testAIRouterUsesRoutingPreferenceForFallbackOrder() {
    let settings = AppSettings()
    var provider = AIProvider(name: "Mixed", apiProtocol: .openAI,
                              baseURL: "https://mixed.test/v1",
                              apiKey: "key",
                              models: [
                                AIModelEntry(name: "claude-opus-200k"),
                                AIModelEntry(name: "gpt-4o-mini")
                              ])
    provider.isEnabled = true
    settings.providers = [provider]
    settings.activeProviderID = provider.id
    settings.activeModel = "claude-opus-200k"
    settings.autoRouteEnabled = true
    settings.fallbackEnabled = false
    settings.routingPreference = .fastest

    let fastestRoutes = AIRequestRouter.candidates(settings: settings,
                                                   action: AIAction.defaults()[0],
                                                   sourceText: "short",
                                                   hasImage: false)
    expect(fastestRoutes.first?.modelName == "claude-opus-200k", "keeps explicit active model first")
    expect(fastestRoutes.dropFirst().first?.modelName == "gpt-4o-mini", "fast preference promotes fast fallback")
    expect(fastestRoutes.dropFirst().first?.reason == "速度偏好优先", "labels fast preference route")

    settings.routingPreference = .quality
    settings.activeModel = "gpt-4o-mini"
    let qualityRoutes = AIRequestRouter.candidates(settings: settings,
                                                   action: AIAction.defaults()[0],
                                                   sourceText: "short",
                                                   hasImage: false)
    expect(qualityRoutes.first?.modelName == "gpt-4o-mini", "keeps explicit active fast model first")
    expect(qualityRoutes.dropFirst().first?.modelName == "claude-opus-200k", "quality preference promotes capable fallback")
    expect(qualityRoutes.dropFirst().first?.reason == "质量偏好优先", "labels quality preference route")
}

func testAIRouterUsesRoutingPreferenceWhenOnlyFallbackIsEnabled() {
    let settings = AppSettings()
    var provider = AIProvider(name: "Mixed", apiProtocol: .openAI,
                              baseURL: "https://mixed.test/v1",
                              apiKey: "key",
                              models: [
                                AIModelEntry(name: "claude-opus-200k"),
                                AIModelEntry(name: "gpt-4o-mini")
                              ])
    provider.isEnabled = true
    settings.providers = [provider]
    settings.activeProviderID = provider.id
    settings.activeModel = "claude-opus-200k"
    settings.autoRouteEnabled = false
    settings.fallbackEnabled = true
    settings.routingPreference = .fastest

    let routes = AIRequestRouter.candidates(settings: settings,
                                            action: AIAction.defaults()[0],
                                            sourceText: "short",
                                            hasImage: false)
    expect(routes.first?.modelName == "claude-opus-200k", "keeps current route first without auto routing")
    expect(routes.dropFirst().first?.modelName == "gpt-4o-mini", "orders fallback candidates by routing preference")
}

func testAIRouterPrefersLocalModelRoutesInPrivacyMode() {
    let settings = AppSettings()
    var cloud = AIProvider(name: "OpenAI", apiProtocol: .openAI,
                           baseURL: "https://api.openai.test/v1",
                           apiKey: "key",
                           models: [AIModelEntry(name: "gpt-4o-mini")])
    var local = AIProvider.preset(.lmStudio)
    local.models = [AIModelEntry(name: "local-chat")]
    cloud.isEnabled = true
    local.isEnabled = true
    settings.providers = [cloud, local]
    settings.activeProviderID = cloud.id
    settings.activeModel = "gpt-4o-mini"
    settings.applyWorkMode(.privacy)

    let privacyRoutes = AIRequestRouter.candidates(settings: settings,
                                                   action: AIAction.defaults()[0],
                                                   sourceText: "需要在本地处理的隐私内容",
                                                   hasImage: false)
    expect(privacyRoutes.first?.providerID == local.id,
           "privacy mode auto routing promotes a local model ahead of the active cloud model")
    expect(privacyRoutes.first?.reason == "本地隐私优先",
           "privacy mode explains local-first routing")
    expect(privacyRoutes.dropFirst().contains { $0.providerID == cloud.id && $0.modelName == "gpt-4o-mini" },
           "privacy mode keeps the cloud model as a later fallback candidate")
    expect(privacyRoutes.dropFirst().first { $0.providerID == cloud.id }?.reason == "云端备用模型",
           "privacy mode labels cloud fallback candidates explicitly")

    let pipeline = ActionPipelineDiagnostic.make(action: AIAction.defaults()[0],
                                                 settings: settings,
                                                 hasImage: false)
    let diagnostics = AIRequestDiagnostics(actionName: "提问",
                                           sourceCharacterCount: 12,
                                           hasImage: false,
                                           fallbackEnabled: settings.fallbackEnabled,
                                           autoRouteEnabled: settings.autoRouteEnabled,
                                           routingPreference: settings.routingPreference,
                                           candidateCount: privacyRoutes.count,
                                           actionPipeline: pipeline,
                                           candidateRoutes: privacyRoutes)
    expect(diagnostics.cloudFallbackReviewSummary == "confirmation-required; local=1; cloud=1",
           "privacy mode request diagnostics require confirmation before cloud fallback")
    expect(diagnostics.requiresCloudFallbackConfirmation(from: privacyRoutes[0],
                                                         to: privacyRoutes.dropFirst().first { !$0.isLocalEndpoint }),
           "privacy mode blocks silent fallback from local to cloud")

    settings.autoRouteEnabled = false
    settings.fallbackEnabled = true
    let manualRoutes = AIRequestRouter.candidates(settings: settings,
                                                  action: AIAction.defaults()[0],
                                                  sourceText: "需要在本地处理的隐私内容",
                                                  hasImage: false)
    expect(manualRoutes.first?.providerID == cloud.id,
           "manual routing still honors the explicitly selected cloud model")
}

func testAIRouterUsesStableConfiguredOrderForEqualScores() {
    let settings = AppSettings()
    var firstProvider = AIProvider(name: "First", apiProtocol: .openAI,
                                   baseURL: "https://first.test/v1",
                                   apiKey: "key",
                                   models: [
                                    AIModelEntry(name: "plain-active"),
                                    AIModelEntry(name: "plain-first")
                                   ])
    var secondProvider = AIProvider(name: "Second", apiProtocol: .openAI,
                                    baseURL: "https://second.test/v1",
                                    apiKey: "key",
                                    models: [AIModelEntry(name: "plain-second")])
    firstProvider.isEnabled = true
    secondProvider.isEnabled = true
    settings.providers = [firstProvider, secondProvider]
    settings.activeProviderID = firstProvider.id
    settings.activeModel = "plain-active"
    settings.autoRouteEnabled = false
    settings.fallbackEnabled = true

    let routes = AIRequestRouter.candidates(settings: settings,
                                            action: AIAction.defaults()[0],
                                            sourceText: "short",
                                            hasImage: false)
    expect(routes.map(\.modelName) == ["plain-active", "plain-first", "plain-second"],
           "uses configured provider/model order when fallback scores tie")
}

func testPrivacyRedactionDefaults() {
    let defaultRules = PrivacyRedactionRule.defaults()
    expect(defaultRules.contains { $0.name == "API Key 与访问令牌" },
           "default redaction rules expose token detection as a readable rule")
    expect(defaultRules.contains { $0.name == "私钥与 JWT" },
           "default redaction rules expose private key and JWT detection as a readable rule")
    expect(defaultRules.allSatisfy { PrivacyFilter.validatePattern($0.pattern) == nil },
           "default redaction rules are valid")

    let slackToken = "xoxb-" + "123456789012-" + "abcdefghijklmnopqrstuvwxyz"
    let text = """
    联系我 test@example.com 或 13800138000,
    token sk-abcdefghijklmnopqrstuvwxyz
    openai sk-proj-abcdefghijklmnopqrstuvwxyz-1234567890
    github ghp_abcdefghijklmnopqrstuvwxyz123456
    github fine github_pat_abcdefghijklmnopqrstuvwxyz1234567890
    slack \(slackToken)
    aws AKIA1234567890ABCDEF
    google AIzaabcdefghijklmnopqrstuvwxyz1234567890
    callback https://example.test/callback?access_token=visible-access-token&client_secret=query-client-secret-value&ok=true
    jwt eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.VerySecretSignatureValue1234567890
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAASecretPrivateKeyBody
    -----END OPENSSH PRIVATE KEY-----
    api_key=abcdefghijklmnopqrstuvwxyz
    secret: abcdefghijklmnopqrstuvwxyz
    """
    let redacted = PrivacyFilter.apply(to: text, rules: defaultRules)
    expect(!redacted.contains("test@example.com"), "redacts email")
    expect(!redacted.contains("13800138000"), "redacts phone")
    expect(!redacted.contains("sk-abcdefghijklmnopqrstuvwxyz"), "redacts classic sk token")
    expect(!redacted.contains("sk-proj-abcdefghijklmnopqrstuvwxyz-1234567890"), "redacts multi-part OpenAI token")
    expect(!redacted.contains("ghp_abcdefghijklmnopqrstuvwxyz123456"), "redacts GitHub token")
    expect(!redacted.contains("github_pat_abcdefghijklmnopqrstuvwxyz1234567890"), "redacts GitHub fine-grained token")
    expect(!redacted.contains(slackToken), "redacts Slack token")
    expect(!redacted.contains("AKIA1234567890ABCDEF"), "redacts AWS access key id")
    expect(!redacted.contains("AIzaabcdefghijklmnopqrstuvwxyz1234567890"), "redacts Google API key")
    expect(!redacted.contains("visible-access-token"), "redacts access token query parameter")
    expect(!redacted.contains("query-client-secret-value"), "redacts client secret query parameter")
    expect(!redacted.contains("VerySecretSignatureValue1234567890"), "redacts JWT")
    expect(!redacted.contains("SecretPrivateKeyBody"), "redacts PEM private key body")
    expect(redacted.contains("ok=true"), "keeps unrelated query parameters")
    expect(!redacted.contains("api_key=abcdefghijklmnopqrstuvwxyz"), "redacts api_key field")
    expect(!redacted.contains("secret: abcdefghijklmnopqrstuvwxyz"), "redacts secret field")
    expect(redacted.contains("[邮箱]"), "uses email replacement")
    expect(redacted.contains("[手机号]"), "uses phone replacement")
    expect(redacted.components(separatedBy: "[密钥]").count >= 10, "uses key replacement for common token formats")
}

func testPrivacyRedactionDefaultSampleDemonstratesSensitiveFormats() {
    let sample = PrivacyFilter.defaultSampleText
    let preview = PrivacyFilter.preview(text: sample, rules: PrivacyRedactionRule.defaults())

    expect(sample.contains("test@example.com"), "default redaction sample includes email")
    expect(sample.contains("13800138000"), "default redaction sample includes phone")
    expect(sample.contains("sk-live-secret-value-1234567890"), "default redaction sample includes api key")
    expect(sample.contains("access_token=visible-access-token"), "default redaction sample includes query token")
    expect(PrivacyFilter.defaultSampleLineCount >= 3, "default redaction sample exposes multiple example lines")
    expect(PrivacyFilter.defaultSampleEditorHeight >= Double(PrivacyFilter.defaultSampleLineCount) * PrivacyFilter.defaultSampleEditorLineHeight,
           "default redaction sample editor height scales with sample lines")
    expect(preview.totalMatches >= 4, "default redaction sample demonstrates multiple built-in detectors")
    expect(!preview.output.contains("test@example.com"), "default redaction sample redacts email")
    expect(!preview.output.contains("13800138000"), "default redaction sample redacts phone")
    expect(!preview.output.contains("sk-live-secret-value-1234567890"), "default redaction sample redacts api key")
    expect(!preview.output.contains("visible-access-token"), "default redaction sample redacts query token")
    expect(preview.output.contains("ok=true"), "default redaction sample keeps unrelated query parameters")
}

func testPrivacyRedactionPreviewReportsInvalidRules() {
    let valid = PrivacyRedactionRule(name: "邮箱",
                                     pattern: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
                                     replacement: "[邮箱]")
    let invalid = PrivacyRedactionRule(name: "坏规则",
                                       pattern: #"("#,
                                       replacement: "[坏]")
    let preview = PrivacyFilter.preview(text: "a@example.com b@example.com",
                                        rules: [valid, invalid])
    expect(preview.output == "[邮箱] [邮箱]", "valid rules still apply when another rule is invalid")
    expect(preview.totalMatches == 2, "reports total match count")
    expect(preview.invalidReports.count == 1, "reports invalid regex")
    expect(preview.invalidReports.first?.ruleName == "坏规则", "keeps invalid rule name")
    expect(PrivacyFilter.validatePattern(#"\d+"#) == nil, "accepts valid regex")
    expect(PrivacyFilter.validatePattern(#"("#) != nil, "rejects invalid regex")
}

func testPrivacyRedactionGuardsRiskyRulesAndLongReplacement() {
    let risky = PrivacyRedactionRule(name: "高风险",
                                     pattern: #"(.+)+"#,
                                     replacement: "[隐藏]")
    let overlongPattern = PrivacyRedactionRule(name: "过长",
                                               pattern: String(repeating: "a", count: PrivacyFilter.maxPatternLength + 1),
                                               replacement: "[长]")
    let longReplacement = String(repeating: "x", count: PrivacyFilter.maxReplacementLength + 20)
    let replacementRule = PrivacyRedactionRule(name: "数字",
                                               pattern: #"\d"#,
                                               replacement: longReplacement)

    let preview = PrivacyFilter.preview(text: "code 12",
                                        rules: [risky, overlongPattern, replacementRule])

    expect(preview.invalidReports.count == 2, "reports risky and overlong redaction rules as invalid")
    expect(preview.invalidReports.contains { $0.ruleName == "高风险" && ($0.errorMessage?.contains("高风险") == true) },
           "explains risky wildcard quantifier rules")
    expect(preview.invalidReports.contains { $0.ruleName == "过长" && ($0.errorMessage?.contains("过长") == true) },
           "explains overlong redaction patterns")
    expect(PrivacyFilter.validatePattern(#"(.+)+"#) != nil,
           "rejects risky wildcard nested quantifier patterns")
    expect(PrivacyFilter.validatePattern(String(repeating: "a", count: PrivacyFilter.maxPatternLength + 1)) != nil,
           "rejects overlong redaction patterns")

    let expectedReplacement = String(repeating: "x", count: PrivacyFilter.maxReplacementLength)
    expect(preview.output == "code \(expectedReplacement)\(expectedReplacement)",
           "uses capped replacement text to avoid output explosion")
    let replacementReport = preview.reports.first { $0.ruleName == "数字" }
    expect(replacementReport?.matchCount == 2, "still reports matches for capped replacement rules")
    expect(replacementReport?.statusText.contains("替换文本已截断") == true,
           "warns when replacement text is capped")
}

func testPrivacySubmissionPreviewExplainsFinalPayload() {
    var action = AIAction.defaults()[0]
    action.name = "提问"
    action.prompt = "处理:\n{{text}}"
    let preview = PrivacyFilter.preview(text: "联系 test@example.com",
                                        rules: [PrivacyRedactionRule(
                                            name: "邮箱",
                                            pattern: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
                                            replacement: "[邮箱]"
                                        )])
    let submission = PrivacySubmissionPreview(action: action,
                                              originalText: "联系 test@example.com",
                                              redactionPreview: preview,
                                              systemPrompt: "系统提示",
                                              redactionEnabled: true,
                                              hasImage: true,
                                              historyContentStorage: .metadataOnly)
    expect(submission.processedText == "联系 [邮箱]", "uses redacted text as payload")
    expect(submission.totalRedactionMatches == 1, "reports redaction match count")
    expect(submission.invalidRedactionRuleCount == 0, "reports invalid rule count")
    expect(submission.summaryText.contains("附加内容: 1 张图片"), "reports image attachment")
    expect(submission.summaryText.contains("保存历史: 是"), "reports history policy")
    expect(submission.summaryText.contains("历史内容: 仅元信息"), "reports history content storage policy")
    expect(submission.summaryText.contains("隐私风险: 风险中"),
           "reports local privacy risk in submission summary")
    expect(submission.summaryText.contains("隐私建议: 发送前预览并确认; 确认图片不含敏感信息"),
           "submission summary reports actionable privacy recovery guidance")
    let userEnabledRequirement = submission.previewRequirement(userPreferenceEnabled: true)
    expect(submission.summaryText(previewRequirement: userEnabledRequirement).contains("预览原因: 用户开启"),
           "submission summary can explain user-enabled privacy preview")
    expect(submission.contentText(previewRequirement: userEnabledRequirement).contains("预览原因: 用户开启"),
           "privacy preview content explains user-enabled preview reason")
    expect(submission.contentText.contains("本地脱敏: 已启用,命中 1 处,失效规则 0 条"), "explains redaction state")
    expect(submission.contentText.contains("疑似敏感 1 处"),
           "privacy preview risk summary uses counts instead of sensitive content")
    expect(submission.contentText.contains("处理:\n联系 [邮箱]"), "renders final user prompt")
    expect(!submission.contentText.contains("test@example.com"), "does not expose redacted sensitive text")
    let diagnostic = submission.diagnostic(previewRequired: true)
    expect(diagnostic.originalCharacterCount == 19, "diagnostic reports original length")
    expect(diagnostic.submittedCharacterCount == 7, "diagnostic reports submitted length")
    expect(diagnostic.redactionMatchCount == 1, "diagnostic reports redaction matches")
    expect(diagnostic.invalidRedactionRuleCount == 0, "diagnostic reports invalid rule count")
    expect(diagnostic.saveHistoryEnabled, "diagnostic reports history policy")
    expect(diagnostic.historyContentStorage == .metadataOnly, "diagnostic reports history content storage policy")
    expect(diagnostic.previewRequired, "diagnostic reports preview requirement")
    expect(diagnostic.riskAssessment.level == .medium, "diagnostic reports medium risk for redacted sensitive text with image")
    expect(diagnostic.riskAssessment.recoverySuggestion == "发送前预览并确认; 确认图片不含敏感信息",
           "medium image privacy risk recommends previewing and checking the image")
    expect(diagnostic.protectionSummaryText == "隐私保护：历史仅元信息",
           "metadata-only submission exposes a concise privacy protection summary")
    expect(diagnostic.summaryLines.contains { $0.contains("Privacy Risk: medium") },
           "diagnostic summary includes machine-readable privacy risk")
    expect(diagnostic.summaryLines.contains("Privacy Recovery: 发送前预览并确认; 确认图片不含敏感信息"),
           "diagnostic summary includes privacy recovery guidance")
    expect(diagnostic.historyTags == ["本地脱敏", "脱敏命中", "隐私风险中", "隐私预览", "仅元信息"],
           "diagnostic produces privacy history tags")
}

func testPrivacySubmissionPreviewReportsRiskWhenRedactionDisabled() {
    var action = AIAction.defaults()[0]
    action.saveHistory = true
    let rawText = "联系 test@example.com 或 13800138000, key sk-live-secret-value-1234567890"
    let submission = PrivacySubmissionPreview(action: action,
                                              originalText: rawText,
                                              redactionPreview: PrivacyRedactionPreview(output: rawText, reports: []),
                                              systemPrompt: "",
                                              redactionEnabled: false,
                                              hasImage: false,
                                              historyContentStorage: .full)

    expect(submission.riskAssessment.level == .high,
           "redaction-disabled sensitive text with full history storage is high risk")
    expect(submission.riskAssessment.detectedSensitiveMatchCount >= 3,
           "risk assessment uses built-in local detectors even when redaction is disabled")
    expect(submission.summaryText.contains("隐私风险: 风险高"),
           "submission summary reports high privacy risk")
    expect(submission.summaryText.contains("隐私建议: 开启本地脱敏; 将历史改为仅元信息; 发送前预览并确认"),
           "submission summary reports high-risk privacy recovery guidance")
    expect(submission.summaryText.contains("疑似敏感"),
           "submission summary reports sensitive counts")
    let diagnostic = submission.diagnostic(previewRequired: false)
    expect(diagnostic.summaryLines.contains { $0.contains("Privacy Risk: high") },
           "diagnostic summary includes high privacy risk")
    expect(diagnostic.summaryLines.contains("Privacy Recovery: 开启本地脱敏; 将历史改为仅元信息; 发送前预览并确认"),
           "high-risk diagnostics recommend redaction, metadata-only history, and preview")
    expect(diagnostic.highRiskHistoryProtectionEnabled,
           "high-risk full-history submissions enable metadata-only history protection")
    expect(diagnostic.contentExportProtectionEnabled,
           "high-risk submissions protect conversation markdown exports")
    expect(diagnostic.effectiveHistoryContentStorage == .metadataOnly,
           "high-risk full-history submissions are stored as metadata only")
    expect(diagnostic.historyStorageSummary == "仅元信息 (高风险保护)",
           "high-risk history protection is visible in diagnostics")
    expect(diagnostic.summaryLines.contains("Configured History Content Storage: 完整保存"),
           "diagnostic preserves the configured history storage mode")
    expect(diagnostic.summaryLines.contains("Content Export Protected: yes"),
           "diagnostic reports high-risk content export protection")
    expect(diagnostic.protectionSummaryText == "隐私保护：历史仅元信息，导出省略正文",
           "high-risk full-history submissions expose a concise protection summary")
    expect(diagnostic.historyTags == ["隐私风险高", "仅元信息"],
           "diagnostic tags high-risk submissions and metadata-only protection for history audit")
}

func testPrivacySubmissionPreviewDetectsExpandedSecretFormatsWhenRedactionDisabled() {
    var action = AIAction.defaults()[0]
    action.saveHistory = true
    let rawText = """
    jwt eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.VerySecretSignatureValue1234567890
    callback https://example.test/callback?access_token=visible-access-token&client_secret=query-client-secret-value&ok=true
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAASecretPrivateKeyBody
    -----END OPENSSH PRIVATE KEY-----
    """
    let submission = PrivacySubmissionPreview(action: action,
                                              originalText: rawText,
                                              redactionPreview: PrivacyRedactionPreview(output: rawText, reports: []),
                                              systemPrompt: "",
                                              redactionEnabled: false,
                                              hasImage: false,
                                              historyContentStorage: .full)

    expect(submission.riskAssessment.level == .high,
           "expanded secret formats are high risk even when local redaction is disabled")
    expect(submission.riskAssessment.detectedSensitiveMatchCount >= 3,
           "risk assessment counts JWT, query secrets, and private keys via built-in detectors")
    expect(submission.previewRequirement(userPreferenceEnabled: false).reason == .highPrivacyRisk,
           "expanded secret formats force privacy preview")
    let diagnostic = submission.diagnostic(previewRequirement: submission.previewRequirement(userPreferenceEnabled: false))
    expect(diagnostic.highRiskHistoryProtectionEnabled,
           "expanded secret formats trigger metadata-only history protection")
    expect(diagnostic.contentExportProtectionEnabled,
           "expanded secret formats protect conversation export content")
    expect(diagnostic.historyTags == ["隐私风险高", "隐私预览", "仅元信息"],
           "expanded secret formats write audit-friendly privacy tags")
}

func testPrivacySubmissionPreviewRequirementProtectsHighRiskPayloads() {
    var action = AIAction.defaults()[0]
    action.saveHistory = true

    let lowRisk = PrivacySubmissionPreview(action: action,
                                           originalText: "普通问题",
                                           redactionPreview: PrivacyRedactionPreview(output: "普通问题", reports: []),
                                           systemPrompt: "",
                                           redactionEnabled: false,
                                           hasImage: false,
                                           historyContentStorage: .full)
    let lowRequirement = lowRisk.previewRequirement(userPreferenceEnabled: false)
    expect(!lowRequirement.isRequired, "low-risk payloads respect disabled privacy preview")
    expect(lowRequirement.reason == .notRequired, "low-risk disabled preview uses not-required reason")

    let userEnabledRequirement = lowRisk.previewRequirement(userPreferenceEnabled: true)
    expect(userEnabledRequirement.isRequired, "user-enabled privacy preview still requires confirmation")
    expect(userEnabledRequirement.reason == .userEnabled, "user-enabled privacy preview records its reason")
    expect(userEnabledRequirement.confirmationMessage(redactionEnabled: true).contains("你已开启发送前预览"),
           "user-enabled privacy preview confirmation explains the user setting")
    expect(userEnabledRequirement.confirmationMessage(redactionEnabled: true).contains("本地脱敏"),
           "user-enabled privacy preview confirmation mentions redaction when enabled")
    expect(userEnabledRequirement.confirmationMessage(redactionEnabled: false).contains("最终 Prompt"),
           "user-enabled privacy preview confirmation mentions final prompt when redaction is disabled")
    expect(lowRequirement.confirmationMessage(redactionEnabled: false).contains("即将发送给 AI"),
           "not-required confirmation message still describes the final payload when reused")

    let rawText = "联系 test@example.com 或 13800138000, key sk-live-secret-value-1234567890"
    let highRisk = PrivacySubmissionPreview(action: action,
                                            originalText: rawText,
                                            redactionPreview: PrivacyRedactionPreview(output: rawText, reports: []),
                                            systemPrompt: "",
                                            redactionEnabled: false,
                                            hasImage: false,
                                            historyContentStorage: .full)
    let forcedRequirement = highRisk.previewRequirement(userPreferenceEnabled: false)
    expect(forcedRequirement.isRequired, "high-risk payloads force privacy preview even when disabled")
    expect(forcedRequirement.reason == .highPrivacyRisk, "forced high-risk preview records its reason")
    expect(forcedRequirement.confirmationMessage(redactionEnabled: false).contains("高隐私风险"),
           "forced high-risk confirmation explains the risk reason")
    expect(highRisk.previewRequirement(userPreferenceEnabled: true).reason == .highPrivacyRisk,
           "high-risk reason takes precedence over the general user-enabled preview setting")

    let diagnostic = highRisk.diagnostic(previewRequirement: forcedRequirement)
    expect(diagnostic.previewRequired, "high-risk diagnostic records forced preview")
    expect(diagnostic.previewReason == .highPrivacyRisk, "high-risk diagnostic records forced preview reason")
    expect(highRisk.contentText(previewRequirement: forcedRequirement).contains("预览原因: 高隐私风险"),
           "high-risk privacy preview content explains forced preview reason")
    expect(diagnostic.summaryLines.contains("Preview Reason: high-privacy-risk"),
           "diagnostic summary exposes the forced preview reason without sensitive content")
    expect(diagnostic.historyTags == ["隐私风险高", "隐私预览", "仅元信息"],
           "forced high-risk preview writes audit-friendly history tags")

    var noHistoryAction = action
    noHistoryAction.saveHistory = false
    let highRiskNoHistory = PrivacySubmissionPreview(action: noHistoryAction,
                                                     originalText: rawText,
                                                     redactionPreview: PrivacyRedactionPreview(output: rawText, reports: []),
                                                     systemPrompt: "",
                                                     redactionEnabled: false,
                                                     hasImage: false,
                                                     historyContentStorage: .full)
    let noHistoryRequirement = highRiskNoHistory.previewRequirement(userPreferenceEnabled: false)
    let noHistoryDiagnostic = highRiskNoHistory.diagnostic(previewRequirement: noHistoryRequirement)
    expect(noHistoryDiagnostic.previewReason == .highPrivacyRisk,
           "high-risk no-history payloads still force privacy preview")
    expect(!noHistoryDiagnostic.highRiskHistoryProtectionEnabled,
           "no-history high-risk payloads do not need history storage downgrade")
    expect(noHistoryDiagnostic.effectiveHistoryContentStorage == nil,
           "no-history high-risk payloads still avoid history storage")
    expect(noHistoryDiagnostic.contentExportProtectionEnabled,
           "no-history high-risk payloads still protect conversation exports")
    expect(noHistoryDiagnostic.protectionSummaryText == "隐私保护：不保存历史，导出省略正文",
           "no-history high-risk payloads expose a concise protection summary")
    expect(noHistoryDiagnostic.historyTags == ["隐私风险高", "隐私预览", "不保存历史"],
           "no-history high-risk payloads keep audit tags without metadata-only tag")
}

func testPrivacySubmissionPreviewReportsInvalidRules() {
    let invalid = PrivacyRedactionRule(name: "坏规则",
                                       pattern: #"("#,
                                       replacement: "[坏]")
    let preview = PrivacyFilter.preview(text: "hello", rules: [invalid])
    let submission = PrivacySubmissionPreview(action: AIAction.defaults()[0],
                                              originalText: "hello",
                                              redactionPreview: preview,
                                              systemPrompt: "",
                                              redactionEnabled: true,
                                              hasImage: false)
    expect(submission.invalidRedactionRuleCount == 1, "counts invalid redaction rules")
    expect(submission.contentText.contains("坏规则"), "includes invalid rule name")
    expect(submission.contentText.contains("规则错误"), "includes invalid rule status")
    expect(submission.contentText.contains("System Prompt:\n(空)"), "shows empty system prompt explicitly")
    expect(submission.contentText.contains("隐私建议: 修复失效脱敏规则"),
           "privacy preview content recommends fixing invalid redaction rules")
    expect(submission.diagnostic(previewRequired: false).historyTags == ["本地脱敏", "脱敏规则异常"],
           "diagnostic tags invalid redaction rules")
    expect(submission.diagnostic(previewRequired: false).summaryLines.contains("Privacy Recovery: 修复失效脱敏规则"),
           "invalid redaction rule diagnostics recommend fixing the rule")
}

func testPrivacyHistoryTagExportPriorityIncludesMetadataOnly() {
    expect(PrivacyHistoryTag.prioritizedForHistoryExport == [
        PrivacyHistoryTag.localRedaction,
        PrivacyHistoryTag.redactionMatched,
        PrivacyHistoryTag.invalidRedactionRule,
        PrivacyHistoryTag.highPrivacyRisk,
        PrivacyHistoryTag.mediumPrivacyRisk,
        PrivacyHistoryTag.privacyPreview,
        PrivacyHistoryTag.metadataOnly
    ], "privacy history export priority keeps metadata-only audit tag")
}

func testAppSettingsAddHistoryPersistsPrivacyTags() {
    let settings = AppSettings()
    settings.historyLimit = 2
    settings.addHistory(action: "总结",
                        source: "联系 [邮箱]",
                        output: "结果",
                        provider: "OpenAI",
                        model: "gpt",
                        tags: ["本地脱敏", "脱敏命中", "本地脱敏"])
    expect(settings.history.first?.displayTags == ["本地脱敏", "脱敏命中"],
           "history preserves privacy tags and display dedupes them")
    expect(settings.history.first?.markdownExport.contains("- 标签: 本地脱敏, 脱敏命中") == true,
           "history export includes privacy tags")
}

func testAppSettingsAddHistoryCanStoreMetadataOnly() {
    let settings = AppSettings()
    settings.historyContentStorage = .metadataOnly
    settings.addHistory(action: "润色",
                        source: "敏感原文 test@example.com",
                        output: "敏感结果 sk-secret-value",
                        provider: "OpenAI",
                        model: "gpt",
                        tags: ["本地脱敏", "本地脱敏", " "])
    let entry = settings.history.first
    expect(entry?.source == "", "metadata-only history omits source text")
    expect(entry?.output == "", "metadata-only history omits output text")
    expect(entry?.displayTags == ["本地脱敏", "仅元信息"],
           "metadata-only history preserves privacy tags and marks metadata-only storage")
    expect(entry?.markdownExport.contains("敏感原文") == false,
           "metadata-only history markdown does not export source text")
    expect(entry?.markdownExport.contains("敏感结果") == false,
           "metadata-only history markdown does not export output text")
}

func testAppSettingsAddHistoryCanOverrideStorageForOneEntry() {
    let settings = AppSettings()
    settings.historyContentStorage = .full
    settings.addHistory(action: "提问",
                        source: "高风险原文 test@example.com",
                        output: "高风险结果 sk-secret-value",
                        provider: "OpenAI",
                        model: "gpt",
                        tags: ["隐私风险高"],
                        contentStorage: .metadataOnly)

    guard let protected = settings.history.first else {
        expect(false, "per-entry protected history is stored")
        return
    }
    expect(settings.historyContentStorage == .full,
           "per-entry history storage override does not change the global setting")
    expect(protected.source == "", "per-entry metadata-only override omits source text")
    expect(protected.output == "", "per-entry metadata-only override omits output text")
    expect(protected.displayTags == ["隐私风险高", "仅元信息"],
           "per-entry metadata-only override marks the history record")
    expect(!protected.markdownExport.contains("test@example.com"),
           "per-entry metadata-only override keeps sensitive source out of markdown export")
    expect(!protected.markdownExport.contains("sk-secret-value"),
           "per-entry metadata-only override keeps sensitive output out of markdown export")

    settings.addHistory(action: "总结",
                        source: "普通原文",
                        output: "普通结果",
                        provider: "OpenAI",
                        model: "gpt")
    expect(settings.history.first?.source == "普通原文",
           "ordinary history keeps full source when no per-entry override is supplied")
    expect(settings.history.first?.output == "普通结果",
           "ordinary history keeps full output when no per-entry override is supplied")
}

func testAppSettingsAddHistoryTruncatesLargeContentAndTags() {
    let settings = AppSettings()
    let source = "SOURCE-START " + String(repeating: "s", count: AppSettings.historySourceCharacterLimit + 200) + " SOURCE-END"
    let output = "OUTPUT-START " + String(repeating: "o", count: AppSettings.historyOutputCharacterLimit + 200) + " OUTPUT-END"
    let longTag = String(repeating: "标签", count: AppSettings.historyTagCharacterLimit)
    let tags = ["项目", "项目", " "] + (0..<(AppSettings.historyTagLimit + 5)).map { "标签\($0)" } + [longTag]

    settings.addHistory(action: String(repeating: "动作", count: 80),
                        source: source,
                        output: output,
                        provider: String(repeating: "Provider", count: 30),
                        model: String(repeating: "model", count: 80),
                        tags: tags)

    guard let entry = settings.history.first else {
        expect(false, "history entry is stored")
        return
    }

    expect(entry.source.count == AppSettings.historySourceCharacterLimit,
           "history source is capped to the configured storage limit")
    expect(entry.output.count == AppSettings.historyOutputCharacterLimit,
           "history output is capped to the configured storage limit")
    expect(entry.source.contains("[SnapAI: 历史记录已截断"), "truncated source includes an explicit marker")
    expect(entry.output.contains("[SnapAI: 历史记录已截断"), "truncated output includes an explicit marker")
    expect(!entry.source.contains("SOURCE-END"), "truncated source drops far-tail content")
    expect(!entry.output.contains("OUTPUT-END"), "truncated output drops far-tail content")
    expect(entry.displayTags.contains(PrivacyHistoryTag.sourceTruncated), "history tags source truncation")
    expect(entry.displayTags.contains(PrivacyHistoryTag.outputTruncated), "history tags output truncation")
    expect(entry.displayTags.count <= AppSettings.historyTagLimit, "history tags are capped")
    expect(!entry.canReopen, "truncated source history cannot be reopened as a full request")
    expect(entry.reopenHelpText == "原文已截断,不能直接重新发起",
           "truncated source history explains why reopen is disabled")
    expect(entry.copyableOutputText?.contains("[SnapAI: 历史记录已截断") == true,
           "copyable truncated output carries the truncation marker")
    expect(entry.actionName.count == AIAction.maxNameLength, "history action names are capped")
    expect(entry.provider.count == AppSettings.importedProviderNameLimit, "history provider names are capped")
    expect(entry.model.count == AppSettings.importedModelNameLimit, "history model names are capped")
}

func testAppSettingsUpdateHistoryTagsSanitizesManualTags() {
    let settings = AppSettings()
    settings.addHistory(action: "总结",
                        source: "原文",
                        output: "结果",
                        provider: "OpenAI",
                        model: "gpt")
    guard let id = settings.history.first?.id else {
        expect(false, "history entry is available for tag update")
        return
    }

    let longTag = String(repeating: "L", count: AppSettings.historyTagCharacterLimit + 10)
    let tags = [" 项目 ", "项目", "", longTag] + (0..<(AppSettings.historyTagLimit + 5)).map { "标签\($0)" }
    settings.updateHistoryTags(id: id, tags: tags)
    let displayTags = settings.history.first?.displayTags ?? []

    expect(displayTags.first == "项目", "manual history tags trim whitespace")
    expect(displayTags.filter { $0 == "项目" }.count == 1, "manual history tags dedupe repeated values")
    expect(displayTags.contains(String(repeating: "L", count: AppSettings.historyTagCharacterLimit)),
           "manual history tags cap long labels")
    expect(displayTags.count == AppSettings.historyTagLimit, "manual history tags are capped")
}

func testSettingsDecodeSanitizesStoredHistory() {
    let settings = AppSettings()
    settings.historyLimit = 50_000
    var first = HistoryEntry(actionName: String(repeating: "动作", count: 80),
                             source: "SOURCE " + String(repeating: "s", count: AppSettings.historySourceCharacterLimit + 20),
                             output: "OUTPUT " + String(repeating: "o", count: AppSettings.historyOutputCharacterLimit + 20),
                             provider: String(repeating: "Provider", count: 30),
                             model: String(repeating: "model", count: 80),
                             tags: ["项目", "项目", " "] + (0..<(AppSettings.historyTagLimit + 10)).map { "标签\($0)" })
    first.id = "duplicate-history"
    var second = HistoryEntry(actionName: "Second",
                              source: "second source",
                              output: "second output",
                              provider: "Provider",
                              model: "model",
                              tags: ["second"])
    second.id = "duplicate-history"
    settings.history = [first, second]

    guard let data = try? JSONEncoder().encode(settings),
          let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else {
        expect(false, "settings history decode succeeds")
        return
    }

    expect(decoded.historyLimit == AppSettings.importedHistoryLimitRange.upperBound,
           "settings decode clamps oversized history limits")
    expect(decoded.history.count == 2, "settings decode keeps available history within the capped limit")
    expect(Set(decoded.history.map(\.id)).count == 2, "settings decode assigns unique history ids")
    guard let entry = decoded.history.first else {
        expect(false, "decoded history has first entry")
        return
    }
    expect(entry.source.count == AppSettings.historySourceCharacterLimit,
           "settings decode caps stored history source")
    expect(entry.output.count == AppSettings.historyOutputCharacterLimit,
           "settings decode caps stored history output")
    expect(entry.displayTags.contains(PrivacyHistoryTag.sourceTruncated),
           "settings decode tags truncated history source")
    expect(entry.displayTags.contains(PrivacyHistoryTag.outputTruncated),
           "settings decode tags truncated history output")
    expect(entry.displayTags.count <= AppSettings.historyTagLimit,
           "settings decode caps stored history tags")
    expect(!entry.canReopen, "settings decode prevents reopening truncated stored source")
    expect(entry.actionName.count == AIAction.maxNameLength,
           "settings decode caps stored history action names")
    expect(entry.provider.count == AppSettings.importedProviderNameLimit,
           "settings decode caps stored history provider names")
    expect(entry.model.count == AppSettings.importedModelNameLimit,
           "settings decode caps stored history model names")
}

func testSettingsClampsStoredPanelDimensions() {
    expect(AppSettings.clampedPanelWidth(.nan) == AppSettings.defaultPanelWidth,
           "panel width clamp falls back for NaN values")
    expect(AppSettings.clampedPanelHeight(.infinity) == AppSettings.defaultPanelHeight,
           "panel height clamp falls back for infinite values")
    expect(AppSettings.clampedPanelWidth(1) == AppSettings.importedPanelWidthRange.lowerBound,
           "panel width clamp enforces minimum usable result window width")
    expect(AppSettings.clampedPanelHeight(1) == AppSettings.importedPanelHeightRange.lowerBound,
           "panel height clamp enforces minimum usable result window height")
    expect(AppSettings.clampedPanelWidth(9_999) == AppSettings.importedPanelWidthRange.upperBound,
           "panel width clamp enforces maximum usable result window width")
    expect(AppSettings.clampedPanelHeight(9_999) == AppSettings.importedPanelHeightRange.upperBound,
           "panel height clamp enforces maximum usable result window height")

    let settings = AppSettings()
    settings.panelWidth = -800
    settings.panelHeight = 20_000
    guard let data = try? JSONEncoder().encode(settings),
          let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else {
        expect(false, "settings panel dimension decode succeeds")
        return
    }

    expect(decoded.panelWidth == AppSettings.importedPanelWidthRange.lowerBound,
           "settings decode clamps undersized stored result window width")
    expect(decoded.panelHeight == AppSettings.importedPanelHeightRange.upperBound,
           "settings decode clamps oversized stored result window height")
}

func testPrivacySubmissionPreviewCanRepresentFollowUpPayload() {
    var action = AIAction.defaults()[0]
    action.prompt = "初始动作:\n{{text}}"
    let preview = PrivacyFilter.preview(text: "继续解释 test@example.com",
                                        rules: [PrivacyRedactionRule(
                                            name: "邮箱",
                                            pattern: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
                                            replacement: "[邮箱]"
                                        )])
    let submission = PrivacySubmissionPreview(action: action,
                                              originalText: "继续解释 test@example.com",
                                              redactionPreview: preview,
                                              systemPrompt: "system",
                                              redactionEnabled: true,
                                              hasImage: false,
                                              userPromptOverride: preview.output)
    expect(submission.userPrompt == "继续解释 [邮箱]", "follow-up preview uses the redacted follow-up text itself")
    expect(!submission.userPrompt.contains("初始动作"), "follow-up preview does not wrap text in the initial action prompt")
    expect(!submission.contentText.contains("test@example.com"), "follow-up preview hides redacted sensitive text")
    expect(submission.diagnostic(previewRequired: true).redactionMatchCount == 1,
           "follow-up diagnostic preserves redaction metadata")
}

func testPrivacySubmissionPreviewRendersSourceResendPayload() {
    var action = AIAction.defaults()[1]
    action.targetLanguage = .english
    let preview = PrivacyFilter.preview(text: "联系 test@example.com",
                                        rules: [PrivacyRedactionRule(
                                            name: "邮箱",
                                            pattern: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
                                            replacement: "[邮箱]"
                                        )])
    let submission = PrivacySubmissionPreview(action: action,
                                              originalText: "联系 test@example.com",
                                              redactionPreview: preview,
                                              systemPrompt: "system",
                                              redactionEnabled: true,
                                              hasImage: false)
    expect(submission.userPrompt.contains("翻译成自然流畅的英语"),
           "source resend preview renders the target action language")
    expect(submission.userPrompt.contains("联系 [邮箱]"),
           "source resend preview renders redacted source text")
    expect(!submission.contentText.contains("test@example.com"),
           "source resend preview does not expose redacted sensitive text")
}

func testTextDiffSummary() {
    let rows = TextDiff.rows(original: "A\nB\nD", revised: "A\nC\nD\nE")
    let summary = TextDiff.summary(for: rows)
    expect(summary.changed == 1, "counts changed lines")
    expect(summary.inserted == 1, "counts inserted lines")
    expect(summary.deleted == 0, "does not count paired change as delete")
    expect(rows.contains { $0.kind == .unchanged && $0.original == "A" }, "keeps common prefix")
    expect(rows.contains { $0.kind == .unchanged && $0.original == "D" }, "keeps common suffix")
}

func testTextDiffCapsLargePreviewRows() {
    let original = (0..<2_000).map { "old-\($0)" }.joined(separator: "\n")
    let revised = (0..<2_000).map { "new-\($0)" }.joined(separator: "\n")
    let rows = TextDiff.rows(original: original, revised: revised, maxRows: 100)
    expect(rows.count == 100, "caps large diff preview rows")
    expect(rows.allSatisfy { $0.kind == .changed }, "keeps changed rows when capped")
}

func testContextProfileEffectiveSystemPrompt() {
    let settings = AppSettings()
    let profile = ContextProfile(name: "项目 A", content: "术语: SnapAI = 菜单栏 AI 工具")
    settings.systemPrompt = "基础提示"
    settings.contextProfiles = [profile]
    settings.activeContextProfileID = profile.id
    expect(settings.effectiveSystemPrompt.contains("基础提示"), "keeps base system prompt")
    expect(settings.effectiveSystemPrompt.contains("项目 A"), "includes active context profile name")
    expect(settings.effectiveSystemPrompt.contains("术语"), "includes active context content")

    settings.contextProfiles[0].isEnabled = false
    expect(settings.effectiveSystemPrompt == "基础提示", "ignores disabled context profile")
    let baseOnlyMarkdown = settings.effectiveSystemPromptMarkdownExport
    expect(baseOnlyMarkdown.contains("# SnapAI 实际系统提示"), "effective system prompt markdown has a clear title")
    expect(baseOnlyMarkdown.contains("- 当前上下文包: 无"), "effective system prompt markdown reports missing context")
    expect(baseOnlyMarkdown.contains("基础提示"), "effective system prompt markdown exports base prompt")

    settings.contextProfiles[0].isEnabled = true
    let effectiveMarkdown = settings.effectiveSystemPromptMarkdownExport
    expect(effectiveMarkdown.contains("- 当前上下文包: 项目 A"), "effective system prompt markdown reports active context")
    expect(effectiveMarkdown.contains("当前上下文包: 项目 A"), "effective system prompt markdown includes rendered context block")
    expect(effectiveMarkdown.contains("术语: SnapAI = 菜单栏 AI 工具"), "effective system prompt markdown includes context content")

    let contextStatus = settings.contextStatusMarkdownExport
    expect(contextStatus.contains("# SnapAI 上下文状态"), "context status markdown has a clear title")
    expect(contextStatus.contains("- 上下文包总数: 1"), "context status markdown reports total profile count")
    expect(contextStatus.contains("- 可用上下文包: 1"), "context status markdown reports usable profile count")
    expect(contextStatus.contains("- 当前上下文包: 项目 A"), "context status markdown reports active profile name")
    expect(contextStatus.contains("- 当前上下文字符数: \(profile.content.count)"), "context status markdown reports active context length")
    expect(!contextStatus.contains("术语: SnapAI"), "context status markdown does not expose context content")
    expect(!contextStatus.contains("基础提示"), "context status markdown does not expose base system prompt content")

    let requestContext = AIRequestContextDiagnostic.make(settings: settings)
    expect(requestContext.contextProfileCount == 1, "request context diagnostics reports total profile count")
    expect(requestContext.usableContextProfileCount == 1, "request context diagnostics reports usable profile count")
    expect(requestContext.activeContextCharacterCount == profile.content.count,
           "request context diagnostics reports active context length")
    expect(requestContext.globalSystemPromptCharacterCount == "基础提示".count,
           "request context diagnostics reports base system prompt length")
    expect(requestContext.effectiveSystemPromptCharacterCount == settings.effectiveSystemPrompt.count,
           "request context diagnostics reports effective system prompt length")
    let requestContextSummary = requestContext.summaryLines.joined(separator: "\n")
    expect(requestContextSummary.contains("Active Context: set"), "request context diagnostics reports active context presence")
    expect(!requestContextSummary.contains("项目 A"), "request context diagnostics does not expose context profile name")
    expect(!requestContextSummary.contains("术语: SnapAI"), "request context diagnostics does not expose context content")
    expect(!requestContextSummary.contains("基础提示"), "request context diagnostics does not expose system prompt content")

    let markdown = profile.markdownExport(isActive: true)
    expect(markdown.contains("# 项目 A"), "context profile markdown exports the profile name")
    expect(markdown.contains("- 状态: 使用中"), "context profile markdown exports active state")
    expect(markdown.contains("- 启用: 是"), "context profile markdown exports enabled state")
    expect(markdown.contains("- 字符数: \(profile.content.count)"), "context profile markdown exports content length")
    expect(markdown.contains("## 内容\n\n术语: SnapAI = 菜单栏 AI 工具"), "context profile markdown exports content")

    let blank = ContextProfile(name: " \n ", content: " \n ", isEnabled: false)
    expect(blank.markdownExport(isActive: false).contains("# 未命名上下文"), "blank context profile markdown uses fallback name")
    expect(blank.markdownExport(isActive: false).contains("无内容"), "blank context profile markdown explains empty content")

    let unsafeProfile = ContextProfile(name: "项目\n# 注入|`名称`",
                                       content: "术语\n保留正文换行")
    settings.contextProfiles = [unsafeProfile]
    settings.activeContextProfileID = unsafeProfile.id
    let unsafePrompt = settings.effectiveSystemPrompt
    expect(unsafePrompt.contains("当前上下文包: 项目 # 注入/'名称'"),
           "effective system prompt keeps context profile name single-line")
    expect(!unsafePrompt.contains("项目\n# 注入"), "effective system prompt does not allow context name newline injection")
    expect(unsafePrompt.contains("术语\n保留正文换行"), "effective system prompt preserves context content newlines")

    let unsafeProfileMarkdown = unsafeProfile.markdownExport(isActive: true)
    expect(unsafeProfileMarkdown.contains("# 项目 # 注入/'名称'"),
           "context profile markdown keeps unsafe names single-line")
    expect(!unsafeProfileMarkdown.contains("项目\n# 注入"),
           "context profile markdown does not allow heading newline injection")
    expect(unsafeProfileMarkdown.contains("## 内容\n\n术语\n保留正文换行"),
           "context profile markdown preserves content newlines")

    let unsafeEffectiveMarkdown = settings.effectiveSystemPromptMarkdownExport
    expect(unsafeEffectiveMarkdown.contains("- 当前上下文包: 项目 # 注入/'名称'"),
           "effective prompt markdown keeps active context name single-line")
    let unsafeStatusMarkdown = settings.contextStatusMarkdownExport
    expect(unsafeStatusMarkdown.contains("- 当前上下文包: 项目 # 注入/'名称'"),
           "context status markdown keeps active context name single-line")
}

func testSettingsCodablePreservesRoutingAndHistoryPreferences() {
    let settings = AppSettings()
    var provider = AIProvider(name: "Provider", apiProtocol: .openAI,
                              baseURL: "https://example.test/v1",
                              apiKey: "secret",
                              models: [AIModelEntry(name: "gpt-4o-mini")])
    provider.isEnabled = true
    settings.providers = [provider]
    settings.activeProviderID = provider.id
    settings.activeModel = "gpt-4o-mini"
    settings.routingPreference = .quality
    settings.autoRouteEnabled = true
    settings.fallbackEnabled = true
    settings.historyContentStorage = .metadataOnly
    settings.actions[0].saveHistory = false

    guard let data = try? JSONEncoder().encode(settings),
          let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else {
        expect(false, "settings encode/decode succeeds")
        return
    }
    expect(decoded.routingPreference == .quality, "preserves routing preference")
    expect(decoded.autoRouteEnabled, "preserves auto route setting")
    expect(decoded.fallbackEnabled, "preserves fallback setting")
    expect(decoded.historyContentStorage == .metadataOnly, "preserves history content storage preference")
    expect(decoded.actions.first?.saveHistory == false, "preserves action history preference")
    expect(decoded.providers.first?.apiKey == "", "does not persist provider api key in JSON")
}

func testSettingsExportConfigurationOmitsSecretsAndHistory() {
    let settings = AppSettings()
    var provider = AIProvider(name: "Provider", apiProtocol: .openAI,
                              baseURL: "https://example.test/v1",
                              apiKey: "sk-proj-export-secret-1234567890",
                              models: [AIModelEntry(name: "gpt-4o-mini")])
    provider.isEnabled = true
    settings.providers = [provider]
    settings.activeProviderID = provider.id
    settings.activeModel = "gpt-4o-mini"
    settings.history = [
        HistoryEntry(actionName: "总结",
                     source: "敏感原文",
                     output: "敏感结果",
                     provider: "Provider",
                     model: "gpt-4o-mini")
    ]
    settings.historyContentStorage = .metadataOnly
    settings.actionUsageCounts = ["敏感动作统计": 42]
    settings.panelWidth = 999
    settings.panelHeight = 777
    settings.iCloudSyncEnabled = true
    settings.onboardingDone = false

    guard let data = settings.exportConfigurationData(),
          let exported = try? JSONDecoder().decode(AppSettings.self, from: data),
          let json = String(data: data, encoding: .utf8) else {
        expect(false, "settings export configuration succeeds")
        return
    }

    expect(!json.contains("sk-proj-export-secret-1234567890"), "exported config omits provider api key")
    expect(!json.contains("敏感原文"), "exported config omits history source")
    expect(!json.contains("敏感结果"), "exported config omits history output")
    expect(!json.contains("敏感动作统计"), "exported config omits action usage statistics")
    expect(exported.providers.first?.apiKey == "", "exported config decodes with empty api key")
    expect(exported.history.isEmpty, "exported config clears history")
    expect(exported.actionUsageCounts.isEmpty, "exported config clears action usage statistics")
    expect(exported.panelWidth == 420 && exported.panelHeight == 360,
           "exported config resets window dimensions")
    expect(!exported.iCloudSyncEnabled, "exported config does not enable iCloud sync on import")
    expect(exported.historyContentStorage == .metadataOnly, "exported config preserves history content storage preference")
    expect(exported.onboardingDone, "exported config marks onboarding as done")
}

func testSettingsSanitizesStoredActionUsageCounts() {
    var counts: [String: Int] = [
        " 润色 ": 2,
        "润色": 3,
        "": 99,
        "负数": -1,
        "零": 0,
        String(repeating: "长", count: AIAction.maxNameLength + 20): AppSettings.importedActionUsageCountRange.upperBound + 100
    ]
    for index in 0..<(AppSettings.importedActionUsageLimit + 5) {
        counts["动作\(index)"] = 1
    }

    let sanitized = AppSettings.sanitizedStoredActionUsageCounts(counts)

    expect(sanitized.count == AppSettings.importedActionUsageLimit,
           "settings caps stored action usage count entries")
    expect(sanitized["润色"] == 5,
           "settings merges stored action usage names after trimming")
    expect(!sanitized.keys.contains(""),
           "settings drops blank stored action usage names")
    expect(!sanitized.keys.contains("负数") && !sanitized.keys.contains("零"),
           "settings drops non-positive stored action usage counts")
    expect(sanitized.keys.contains(String(repeating: "长", count: AIAction.maxNameLength)),
           "settings caps stored action usage names")
    expect(sanitized[String(repeating: "长", count: AIAction.maxNameLength)] == AppSettings.importedActionUsageCountRange.upperBound,
           "settings caps oversized stored action usage counts")

    let settings = AppSettings()
    settings.actionUsageCounts = counts
    guard let data = try? JSONEncoder().encode(settings),
          let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else {
        expect(false, "settings action usage decode succeeds")
        return
    }
    expect(decoded.actionUsageCounts == AppSettings.sanitizedStoredActionUsageCounts(counts),
           "settings decode sanitizes stored action usage counts")
}

func testSettingsRecordActionUsageUsesSafeBounds() {
    let settings = AppSettings()
    let longName = String(repeating: "A", count: AIAction.maxNameLength + 20)
    settings.recordActionUsage(actionName: " \(longName) ")
    expect(settings.actionUsageCounts[String(repeating: "A", count: AIAction.maxNameLength)] == 1,
           "record action usage trims and caps action names")

    settings.actionUsageCounts["溢出"] = AppSettings.importedActionUsageCountRange.upperBound
    settings.recordActionUsage(actionName: "溢出")
    expect(settings.actionUsageCounts["溢出"] == AppSettings.importedActionUsageCountRange.upperBound,
           "record action usage does not exceed the stored usage cap")

    settings.actionUsageCounts["负数"] = -100
    settings.recordActionUsage(actionName: "负数")
    expect(settings.actionUsageCounts["负数"] == 1,
           "record action usage recovers from negative legacy counts")

    settings.recordActionUsage(actionName: " \n ")
    expect(settings.actionUsageCounts["未命名动作"] == 1,
           "record action usage falls back for blank action names")
}

func testSettingsImportProvidersIgnorePlaintextKeys() {
    var imported = AIProvider(name: "Imported", apiProtocol: .openAI,
                              baseURL: "https://imported.test/v1",
                              apiKey: "sk-imported-plaintext-secret",
                              models: [AIModelEntry(name: "gpt")])
    imported.id = "provider-1"

    let restored = AppSettings.providersForImportedConfiguration([imported]) { providerID in
        providerID == "provider-1" ? "keychain-secret" : ""
    }
    expect(restored.first?.apiKey == "keychain-secret",
           "imported providers ignore plaintext file keys and use keychain resolver")

    let stripped = AppSettings.providersForImportedConfiguration([imported]) { _ in "" }
    expect(stripped.first?.apiKey == "",
           "imported providers strip plaintext keys when no local keychain value exists")
}

func testSettingsImportProvidersSanitizeRuntimeBoundaries() {
    var provider = AIProvider(name: String(repeating: "供应商", count: 80),
                              apiProtocol: .openAI,
                              baseURL: String(repeating: "https://example.test/", count: 40),
                              apiKey: "sk-plaintext-provider-key",
                              models: [
                                AIModelEntry(name: " gpt-4o-mini "),
                                AIModelEntry(name: "gpt-4o-mini"),
                                AIModelEntry(name: " "),
                                AIModelEntry(name: String(repeating: "m", count: AppSettings.importedModelNameLimit + 20))
                              ])
    provider.id = "provider-1"
    provider.temperature = 2.5
    provider.maxTokens = AppSettings.importedMaxTokensRange.upperBound + 100
    provider.requestTimeout = AppSettings.importedRequestTimeoutRange.upperBound + 30

    var duplicateProvider = provider
    duplicateProvider.name = "Duplicate"
    duplicateProvider.temperature = .infinity
    duplicateProvider.maxTokens = -10
    duplicateProvider.requestTimeout = -1

    let extras = (0..<(AppSettings.importedProviderLimit + 3)).map { index in
        AIProvider(name: "Extra \(index)",
                   apiProtocol: .openAI,
                   baseURL: "https://extra\(index).test/v1",
                   apiKey: "extra",
                   models: [AIModelEntry(name: "model-\(index)")])
    }

    let sanitized = AppSettings.providersForImportedConfiguration([provider, duplicateProvider] + extras) { providerID in
        providerID == "provider-1" ? "keychain-secret" : ""
    }

    expect(sanitized.count == AppSettings.importedProviderLimit,
           "import caps provider count")
    expect(Set(sanitized.map(\.id)).count == sanitized.count,
           "import assigns unique provider ids")
    expect(sanitized.first?.apiKey == "keychain-secret",
           "import keeps provider keys sourced from keychain")
    expect(sanitized.first?.name.count == AppSettings.importedProviderNameLimit,
           "import caps provider names")
    expect(sanitized.first?.baseURL.count == AppSettings.importedProviderBaseURLLimit,
           "import caps provider base URLs")
    expect(sanitized.first?.temperature == 1,
           "import clamps provider temperature overrides")
    expect(sanitized.first?.maxTokens == AppSettings.importedMaxTokensRange.upperBound,
           "import clamps provider max token overrides")
    expect(sanitized.first?.requestTimeout == AppSettings.importedRequestTimeoutRange.upperBound,
           "import clamps provider timeout overrides")
    expect(sanitized.first?.models.count == 2,
           "import drops blank and duplicate models")
    expect(sanitized.first?.models.first?.name == "gpt-4o-mini",
           "import trims model names")
    expect(sanitized.first?.models.last?.name.count == AppSettings.importedModelNameLimit,
           "import caps model names")
    expect(sanitized.dropFirst().first?.temperature == nil,
           "import drops non-finite provider temperature overrides")
    expect(sanitized.dropFirst().first?.maxTokens == nil,
           "import drops invalid provider max token overrides")
    expect(sanitized.dropFirst().first?.requestTimeout == nil,
           "import drops invalid provider timeout overrides")

    var activeDuplicateProvider = provider
    activeDuplicateProvider.name = "Active Duplicate"
    activeDuplicateProvider.models = [AIModelEntry(name: "duplicate-active-model")]
    let activeConfig = AppSettings.importedProviderConfiguration(
        [provider, activeDuplicateProvider],
        activeProviderID: "provider-1",
        activeModel: " duplicate-active-model "
    ) { providerID in
        providerID == "provider-1" ? "keychain-secret" : ""
    }
    expect(activeConfig.providers.count == 2,
           "import active provider mapping keeps both duplicate-id providers after id repair")
    expect(activeConfig.activeProviderID == activeConfig.providers[1].id,
           "import active provider mapping follows the duplicate provider that contains the active model")
    expect(activeConfig.activeProviderID != "provider-1",
           "import active provider mapping uses the repaired duplicate provider id")
    expect(activeConfig.activeModel == "duplicate-active-model",
           "import active provider mapping trims active model names")
}

func testSettingsImportRemapsActionProviderOverridesAfterProviderIDRepair() {
    let settings = AppSettings()
    var firstProvider = AIProvider(name: "First", apiProtocol: .openAI,
                                   baseURL: "https://first.test/v1",
                                   models: [AIModelEntry(name: "first-model")])
    firstProvider.id = "action-duplicate-provider"
    var secondProvider = AIProvider(name: "Second", apiProtocol: .openAI,
                                    baseURL: "https://second.test/v1",
                                    models: [AIModelEntry(name: "second-model")])
    secondProvider.id = "action-duplicate-provider"
    var action = AIAction(name: "专属动作",
                          prompt: "{{text}}")
    action.providerID = " action-duplicate-provider "
    action.modelOverride = " second-model "
    var invalidModelAction = AIAction(name: "无效专属模型",
                                      prompt: "{{text}}")
    invalidModelAction.providerID = "action-duplicate-provider"
    invalidModelAction.modelOverride = "missing-model"

    settings.providers = [firstProvider, secondProvider]
    settings.activeProviderID = "action-duplicate-provider"
    settings.activeModel = "first-model"
    settings.actions = [action, invalidModelAction]

    settings.normalizeImportedConfiguration()

    expect(settings.providers.count == 2,
           "import keeps duplicate provider entries after repairing ids")
    expect(settings.actions.first?.providerID == settings.providers[1].id,
           "import remaps action provider override to the repaired provider containing its model override")
    expect(settings.actions.first?.modelOverride == "second-model",
           "import trims action model overrides before provider mapping")
    expect(settings.actions.first?.providerID != "action-duplicate-provider",
           "import action provider override uses the repaired duplicate provider id")
    expect(settings.actions.dropFirst().first?.providerID == settings.providers.first?.id,
           "import keeps provider override when model override is invalid")
    expect(settings.actions.dropFirst().first?.modelOverride == nil,
           "import clears invalid action model overrides after provider mapping")
}

func testSettingsDecodeSanitizesStoredProviders() {
    let settings = AppSettings()
    var provider = AIProvider(name: String(repeating: "Provider", count: 40),
                              apiProtocol: .openAI,
                              baseURL: "  " + String(repeating: "https://stored.example/", count: 40) + "  ",
                              apiKey: "runtime-key",
                              models: [
                                AIModelEntry(name: " gpt-4o-mini "),
                                AIModelEntry(name: "gpt-4o-mini"),
                                AIModelEntry(name: " "),
                                AIModelEntry(name: String(repeating: "m", count: AppSettings.importedModelNameLimit + 20))
                              ])
    provider.id = "stored-provider"
    provider.temperature = 2.5
    provider.maxTokens = -10
    provider.requestTimeout = -1

    var duplicateProvider = provider
    duplicateProvider.name = "Duplicate"
    duplicateProvider.models = [AIModelEntry(name: "duplicate-model")]

    let extras = (0..<(AppSettings.importedProviderLimit + 3)).map { index in
        AIProvider(name: "Stored Extra \(index)",
                   apiProtocol: .openAI,
                   baseURL: "https://stored-extra\(index).test/v1",
                   models: [AIModelEntry(name: "stored-extra-model-\(index)")])
    }

    settings.providers = [provider, duplicateProvider] + extras
    settings.activeProviderID = provider.id
    settings.activeModel = "gpt-4o-mini"

    guard let data = try? JSONEncoder().encode(settings),
          let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else {
        expect(false, "settings stored provider decode succeeds")
        return
    }

    expect(decoded.providers.count == AppSettings.importedProviderLimit,
           "settings decode caps stored provider count")
    expect(decoded.providers.first?.id == "stored-provider",
           "settings decode preserves the first valid stored provider id for keychain lookup")
    expect(Set(decoded.providers.map(\.id)).count == decoded.providers.count,
           "settings decode assigns unique ids to duplicate stored providers")
    expect(decoded.providers.first?.name.count == AppSettings.importedProviderNameLimit,
           "settings decode caps stored provider names")
    expect(decoded.providers.first?.baseURL.count == AppSettings.importedProviderBaseURLLimit,
           "settings decode caps stored provider base URLs")
    expect(decoded.providers.first?.temperature == 1,
           "settings decode clamps stored provider temperature overrides")
    expect(decoded.providers.first?.maxTokens == nil,
           "settings decode drops invalid stored provider max token overrides")
    expect(decoded.providers.first?.requestTimeout == nil,
           "settings decode drops invalid stored provider timeout overrides")
    expect(decoded.providers.first?.models.count == 2,
           "settings decode drops blank and duplicate stored models")
    expect(decoded.providers.first?.models.first?.name == "gpt-4o-mini",
           "settings decode trims stored model names")
    expect(decoded.providers.first?.models.last?.name.count == AppSettings.importedModelNameLimit,
           "settings decode caps stored model names")
    expect(decoded.activeProviderID == "stored-provider",
           "settings decode keeps active provider when it remains valid")
    expect(decoded.activeModel == "gpt-4o-mini",
           "settings decode keeps active model after model sanitization")

    let activeDuplicateSettings = AppSettings()
    var firstDuplicate = AIProvider(name: "First", apiProtocol: .openAI,
                                    baseURL: "https://first.test/v1",
                                    models: [AIModelEntry(name: "first-model")])
    firstDuplicate.id = "duplicate-active-provider"
    var secondDuplicate = AIProvider(name: "Second", apiProtocol: .openAI,
                                     baseURL: "https://second.test/v1",
                                     models: [AIModelEntry(name: "second-model")])
    secondDuplicate.id = "duplicate-active-provider"
    activeDuplicateSettings.providers = [firstDuplicate, secondDuplicate]
    activeDuplicateSettings.activeProviderID = "duplicate-active-provider"
    activeDuplicateSettings.activeModel = " second-model "
    var duplicateAction = AIAction(name: "Stored Override", prompt: "{{text}}")
    duplicateAction.providerID = "duplicate-active-provider"
    duplicateAction.modelOverride = "second-model"
    activeDuplicateSettings.actions = [duplicateAction]

    guard let duplicateData = try? JSONEncoder().encode(activeDuplicateSettings),
          let duplicateDecoded = try? JSONDecoder().decode(AppSettings.self, from: duplicateData) else {
        expect(false, "settings decode succeeds for duplicate active provider fixture")
        return
    }
    expect(duplicateDecoded.providers.count == 2,
           "settings decode keeps duplicate-id providers after repairing ids")
    expect(duplicateDecoded.activeProviderID == duplicateDecoded.providers[1].id,
           "settings decode remaps active provider to the repaired duplicate id when its model matches")
    expect(duplicateDecoded.activeProviderID != "duplicate-active-provider",
           "settings decode active provider uses the repaired duplicate id")
    expect(duplicateDecoded.activeModel == "second-model",
           "settings decode trims active model names before normalization")
    expect(duplicateDecoded.actions.first?.providerID == duplicateDecoded.providers[1].id,
           "settings decode remaps action provider overrides to repaired duplicate provider ids")
    expect(duplicateDecoded.actions.first?.modelOverride == "second-model",
           "settings decode preserves action model overrides after provider id repair")
}

func testSettingsDecodeSanitizesStoredRedactionRules() {
    let settings = AppSettings()
    var firstRule = PrivacyRedactionRule(
        name: String(repeating: "规则", count: 80),
        pattern: "  " + #"\d+"# + "  ",
        replacement: String(repeating: "x", count: AppSettings.importedRedactionReplacementLimit + 20)
    )
    firstRule.id = "duplicate-redaction"
    var duplicateRule = PrivacyRedactionRule(
        name: "重复",
        pattern: #"[A-Z]+"#,
        replacement: "[字母]"
    )
    duplicateRule.id = "duplicate-redaction"
    let invalidRule = PrivacyRedactionRule(name: "坏规则",
                                           pattern: "(",
                                           replacement: "[坏]")
    let overlongRule = PrivacyRedactionRule(name: "过长规则",
                                            pattern: String(repeating: "a", count: AppSettings.importedRedactionPatternLimit + 20),
                                            replacement: "[长]")
    let extras = (0..<(AppSettings.importedRedactionRuleLimit + 5)).map { index in
        PrivacyRedactionRule(name: "Extra \(index)",
                             pattern: "extra-\(index)",
                             replacement: "[extra]")
    }
    settings.redactionRules = [firstRule, duplicateRule, invalidRule, overlongRule] + extras

    guard let data = try? JSONEncoder().encode(settings),
          let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else {
        expect(false, "settings stored redaction decode succeeds")
        return
    }

    expect(decoded.redactionRules.count == AppSettings.importedRedactionRuleLimit,
           "settings decode caps stored redaction rule count")
    expect(Set(decoded.redactionRules.map(\.id)).count == decoded.redactionRules.count,
           "settings decode assigns unique ids to duplicate stored redaction rules")
    expect(decoded.redactionRules.first?.name.count == AppSettings.importedRedactionNameLimit,
           "settings decode caps stored redaction rule names")
    expect(decoded.redactionRules.first?.pattern == #"\d+"#,
           "settings decode trims stored redaction patterns")
    expect(decoded.redactionRules.first?.replacement.count == AppSettings.importedRedactionReplacementLimit,
           "settings decode caps stored redaction replacements")
    expect(decoded.redactionRules.contains { $0.name == "坏规则" && $0.pattern == "(" },
           "settings decode preserves invalid stored redaction drafts for UI diagnostics")
    expect(decoded.redactionRules.first { $0.name == "过长规则" }?.pattern.count == AppSettings.importedRedactionPatternLimit,
           "settings decode caps overlong stored redaction patterns")
    expect(AppSettings.sanitizedStoredRedactionRules([]).isEmpty,
           "settings decode preserves explicitly empty stored redaction rule lists")

    let legacyDefaultRules = legacyDefaultRedactionRulesForTests()
    let migratedDefaults = AppSettings.sanitizedStoredRedactionRules(legacyDefaultRules)
    expect(migratedDefaults.map(\.name) == PrivacyRedactionRule.defaults().map(\.name),
           "settings decode migrates exact legacy default redaction rules to current defaults")
    expect(migratedDefaults.contains { $0.name == "私钥与 JWT" },
           "settings decode adds current private-key and JWT redaction rule for legacy defaults")

    var customizedLegacyRules = legacyDefaultRules
    customizedLegacyRules[2].name = "我的密钥规则"
    let preservedCustomRules = AppSettings.sanitizedStoredRedactionRules(customizedLegacyRules)
    expect(preservedCustomRules.map(\.name).contains("我的密钥规则"),
           "settings decode does not replace customized legacy-looking redaction rules")
    expect(!preservedCustomRules.contains { $0.name == "私钥与 JWT" },
           "settings decode avoids injecting new defaults into customized redaction rule sets")
}

func testSettingsLoadPersistsMigratedLegacyRedactionRules() {
    let storageKey = "SnapAI.settings.v1"
    let defaults = UserDefaults.standard
    let previousData = defaults.data(forKey: storageKey)
    defer {
        if let previousData {
            defaults.set(previousData, forKey: storageKey)
        } else {
            defaults.removeObject(forKey: storageKey)
        }
    }

    let settings = AppSettings()
    var provider = AIProvider.preset(.openAI)
    provider.id = "logic-test-redaction-migration-\(UUID().uuidString)"
    provider.apiKey = ""
    settings.providers = [provider]
    settings.activeProviderID = provider.id
    settings.activeModel = provider.enabledModelNames.first ?? "gpt-4o-mini"
    settings.redactionRules = legacyDefaultRedactionRulesForTests()

    guard let encoded = try? JSONEncoder().encode(settings) else {
        expect(false, "settings load migration fixture encodes")
        return
    }
    defaults.set(encoded, forKey: storageKey)

    let loaded = AppSettings.load()
    expect(loaded.redactionRules.map(\.name) == PrivacyRedactionRule.defaults().map(\.name),
           "settings load migrates legacy redaction defaults in memory")

    guard let persistedData = defaults.data(forKey: storageKey),
          let object = try? JSONSerialization.jsonObject(with: persistedData) as? [String: Any],
          let persistedRules = object["redactionRules"] as? [[String: Any]] else {
        expect(false, "settings load migration persists readable settings JSON")
        return
    }
    let persistedNames = persistedRules.compactMap { $0["name"] as? String }
    expect(persistedNames == PrivacyRedactionRule.defaults().map(\.name),
           "settings load writes migrated current redaction defaults back to storage")
    expect(persistedNames.contains("私钥与 JWT"),
           "settings load persists private-key and JWT redaction rule for legacy defaults")
}

func legacyDefaultRedactionRulesForTests() -> [PrivacyRedactionRule] {
    [
        PrivacyRedactionRule(
            name: "邮箱地址",
            pattern: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
            replacement: "[邮箱]"
        ),
        PrivacyRedactionRule(
            name: "手机号",
            pattern: #"(?<!\d)(?:\+?86[- ]?)?1[3-9]\d{9}(?!\d)"#,
            replacement: "[手机号]"
        ),
        PrivacyRedactionRule(
            name: "疑似 API Key",
            pattern: #"(?i)\b(?:sk(?:-[a-z0-9]+)+|gh[pousr]_[a-z0-9_]{20,}|xox[baprs]-[a-z0-9-]{20,}|(?:api[_-]?key|token|secret)[_:\-= ]+[a-z0-9][a-z0-9._-]{11,})\b"#,
            replacement: "[密钥]"
        )
    ]
}

func testSettingsImportSanitizesUnsafeConfiguration() {
    let settings = AppSettings()
    settings.temperature = 2.5
    settings.historyLimit = 50_000
    settings.askPrompt = " \n"
    settings.translatePrompt = String(repeating: "t", count: AppSettings.importedPromptLimit + 25)
    settings.systemPrompt = "\n\t"

    var firstRule = PrivacyRedactionRule(
        name: String(repeating: "规则", count: 80),
        pattern: #"\d+"#,
        replacement: String(repeating: "x", count: AppSettings.importedRedactionReplacementLimit + 20)
    )
    firstRule.id = "duplicate-rule"
    var secondRule = PrivacyRedactionRule(
        name: "字母",
        pattern: #"[A-Z]+"#,
        replacement: "[字母]"
    )
    secondRule.id = "duplicate-rule"
    let invalidRule = PrivacyRedactionRule(name: "坏规则", pattern: "(", replacement: "[坏]")
    let overlongRule = PrivacyRedactionRule(
        name: "过长规则",
        pattern: String(repeating: "a", count: AppSettings.importedRedactionPatternLimit + 1),
        replacement: "[长]"
    )
    settings.redactionRules = [firstRule, secondRule, invalidRule, overlongRule]

    let longContent = String(repeating: "上下文", count: AppSettings.importedContextContentLimit)
    var activeProfile = ContextProfile(
        name: String(repeating: "项目", count: 80),
        content: longContent,
        isEnabled: true
    )
    activeProfile.id = "duplicate-context"
    var duplicateProfile = ContextProfile(name: "备用", content: "备用内容", isEnabled: true)
    duplicateProfile.id = "duplicate-context"
    let blankProfile = ContextProfile(name: "  ", content: "\n", isEnabled: true)
    settings.contextProfiles = [activeProfile, duplicateProfile, blankProfile]
    settings.activeContextProfileID = activeProfile.id

    settings.normalizeImportedConfiguration()

    expect(settings.temperature == 1, "import clamps high temperature to supported range")
    expect(settings.historyLimit == 500, "import clamps history limit to UI-supported range")
    expect(settings.askPrompt == AppSettings.defaultAskPrompt,
           "import replaces blank ask prompts with the default prompt")
    expect(settings.translatePrompt.count == AppSettings.importedPromptLimit,
           "import caps overlong translate prompts")
    expect(settings.systemPrompt == "",
           "import preserves intentionally blank system prompts")
    expect(settings.redactionRules.count == 2, "import drops invalid and overlong redaction rules")
    expect(Set(settings.redactionRules.map(\.id)).count == settings.redactionRules.count,
           "import assigns unique redaction rule ids")
    expect(settings.redactionRules.first?.name.count == AppSettings.importedRedactionNameLimit,
           "import caps redaction rule names")
    expect(settings.redactionRules.first?.replacement.count == AppSettings.importedRedactionReplacementLimit,
           "import caps redaction replacements")
    expect(AppSettings.sanitizedImportedRedactionRules([]).isEmpty,
           "import preserves an explicitly empty redaction rule list")
    let importedLegacyDefaults = AppSettings.sanitizedImportedRedactionRules(legacyDefaultRedactionRulesForTests())
    expect(importedLegacyDefaults.map(\.name) == PrivacyRedactionRule.defaults().map(\.name),
           "import migrates exact legacy default redaction rules to current defaults")
    expect(importedLegacyDefaults.contains { $0.name == "私钥与 JWT" },
           "import adds current private-key and JWT redaction rule for legacy defaults")
    var customizedImportedLegacyRules = legacyDefaultRedactionRulesForTests()
    customizedImportedLegacyRules[2].name = "我的密钥规则"
    let importedCustomRules = AppSettings.sanitizedImportedRedactionRules(customizedImportedLegacyRules)
    expect(importedCustomRules.map(\.name).contains("我的密钥规则"),
           "import preserves customized legacy-looking redaction rule sets")
    expect(!importedCustomRules.contains { $0.name == "私钥与 JWT" },
           "import avoids injecting current defaults into customized redaction rule sets")
    expect(settings.contextProfiles.count == 2, "import drops blank context profiles")
    expect(Set(settings.contextProfiles.map(\.id)).count == settings.contextProfiles.count,
           "import assigns unique context profile ids")
    expect(settings.contextProfiles.first?.name.count == AppSettings.importedContextNameLimit,
           "import caps context profile names")
    expect(settings.contextProfiles.first?.content.count == AppSettings.importedContextContentLimit,
           "import caps context profile content")
    expect(settings.activeContextProfileID == settings.contextProfiles.first?.id,
           "import preserves the active context when it remains usable")
}

func testSettingsDecodeSanitizesStoredContextProfiles() {
    let settings = AppSettings()
    var activeProfile = ContextProfile(
        name: String(repeating: "项目", count: AppSettings.importedContextNameLimit),
        content: String(repeating: "上下文", count: AppSettings.importedContextContentLimit),
        isEnabled: true
    )
    activeProfile.id = "stored-context"
    var duplicateProfile = ContextProfile(name: "备用", content: "备用内容", isEnabled: true)
    duplicateProfile.id = "stored-context"
    let blankProfile = ContextProfile(name: "  ", content: "\n", isEnabled: true)
    settings.contextProfiles = [activeProfile, duplicateProfile, blankProfile]
    settings.activeContextProfileID = activeProfile.id

    guard let data = try? JSONEncoder().encode(settings),
          let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else {
        expect(false, "settings stored context decode succeeds")
        return
    }

    expect(decoded.contextProfiles.count == 2,
           "settings decode drops blank stored context profiles")
    expect(decoded.contextProfiles.first?.id == "stored-context",
           "settings decode preserves first valid stored context profile id")
    expect(Set(decoded.contextProfiles.map(\.id)).count == decoded.contextProfiles.count,
           "settings decode assigns unique ids to duplicate stored context profiles")
    expect(decoded.contextProfiles.first?.name.count == AppSettings.importedContextNameLimit,
           "settings decode caps stored context profile names")
    expect(decoded.contextProfiles.first?.content.count == AppSettings.importedContextContentLimit,
           "settings decode caps stored context profile content")
    expect(decoded.activeContextProfileID == decoded.contextProfiles.first?.id,
           "settings decode keeps active stored context when it remains usable")
    expect(decoded.activeContextProfile?.content.count == AppSettings.importedContextContentLimit,
           "settings decode active context uses sanitized content")
}

func testSettingsDecodeSanitizesStoredPrompts() {
    let settings = AppSettings()
    settings.askPrompt = String(repeating: "a", count: AppSettings.importedPromptLimit + 25)
    settings.translatePrompt = AppSettings.oldDefaultTranslatePrompt
    settings.systemPrompt = String(repeating: "s", count: AppSettings.importedSystemPromptLimit + 25)

    guard let data = try? JSONEncoder().encode(settings),
          let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else {
        expect(false, "settings stored prompt decode succeeds")
        return
    }

    expect(decoded.askPrompt.count == AppSettings.importedPromptLimit,
           "settings decode caps stored ask prompts")
    expect(decoded.translatePrompt == AppSettings.defaultTranslatePrompt,
           "settings decode migrates the old default translate prompt")
    expect(decoded.systemPrompt.count == AppSettings.importedSystemPromptLimit,
           "settings decode caps stored system prompts")

    let blankSettings = AppSettings()
    blankSettings.askPrompt = " \n"
    blankSettings.translatePrompt = "\t"
    blankSettings.systemPrompt = "\n "

    guard let blankData = try? JSONEncoder().encode(blankSettings),
          let blankDecoded = try? JSONDecoder().decode(AppSettings.self, from: blankData) else {
        expect(false, "settings blank prompt decode succeeds")
        return
    }

    expect(blankDecoded.askPrompt == AppSettings.defaultAskPrompt,
           "settings decode replaces blank ask prompts with the default prompt")
    expect(blankDecoded.translatePrompt == AppSettings.defaultTranslatePrompt,
           "settings decode replaces blank translate prompts with the default prompt")
    expect(blankDecoded.systemPrompt == "",
           "settings decode preserves intentionally blank system prompts")
}

func testSettingsDecodeDefaultsRoutingPreference() {
    let json = #"{"settingsSchemaVersion":2,"providers":[]}"#.data(using: .utf8)!
    guard let decoded = try? JSONDecoder().decode(AppSettings.self, from: json) else {
        expect(false, "settings decode succeeds with sparse JSON")
        return
    }
    expect(decoded.routingPreference == .balanced, "defaults missing routing preference to balanced")
    expect(decoded.historyContentStorage == .full, "defaults missing history content storage to full")
}

func testSettingsDecodeDefaultsActiveProviderToFirstProvider() {
    let settings = AppSettings()
    var provider = AIProvider(name: "Provider", apiProtocol: .openAI,
                              baseURL: "https://example.test/v1",
                              apiKey: "secret",
                              models: [AIModelEntry(name: "gpt-4o-mini")])
    provider.isEnabled = true
    settings.providers = [provider]
    settings.activeProviderID = provider.id
    settings.activeModel = "gpt-4o-mini"

    guard let data = try? JSONEncoder().encode(settings),
          var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        expect(false, "settings encode succeeds for active provider fallback fixture")
        return
    }
    object.removeValue(forKey: "activeProviderID")
    guard let stripped = try? JSONSerialization.data(withJSONObject: object),
          let decoded = try? JSONDecoder().decode(AppSettings.self, from: stripped) else {
        expect(false, "settings decode succeeds without activeProviderID")
        return
    }
    expect(decoded.activeProviderID == provider.id, "defaults missing active provider id to first provider")
}

func testSettingsNormalizeActiveSkipsDisabledProviderAndModel() {
    let settings = AppSettings()
    var disabledProvider = AIProvider(name: "Disabled", apiProtocol: .openAI,
                                      baseURL: "https://disabled.test/v1",
                                      apiKey: "key",
                                      models: [AIModelEntry(name: "disabled-provider-model")])
    disabledProvider.isEnabled = false
    var enabledProvider = AIProvider(name: "Enabled", apiProtocol: .openAI,
                                     baseURL: "https://enabled.test/v1",
                                     apiKey: "key",
                                     models: [
                                        AIModelEntry(name: "disabled-model", enabled: false),
                                        AIModelEntry(name: "enabled-model", enabled: true)
                                     ])
    enabledProvider.isEnabled = true
    settings.providers = [disabledProvider, enabledProvider]
    settings.activeProviderID = disabledProvider.id
    settings.activeModel = "disabled-model"

    settings.normalizeActive()

    expect(settings.activeProviderID == enabledProvider.id, "normalizes disabled active provider to first enabled provider")
    expect(settings.activeModel == "enabled-model", "normalizes disabled active model to first enabled model")
}

func testSettingsNormalizeActiveClearsWhenNoEnabledProviderExists() {
    let settings = AppSettings()
    var provider = AIProvider(name: "Disabled", apiProtocol: .openAI,
                              baseURL: "https://disabled.test/v1",
                              apiKey: "key",
                              models: [AIModelEntry(name: "model")])
    provider.isEnabled = false
    settings.providers = [provider]
    settings.activeProviderID = provider.id
    settings.activeModel = "model"

    settings.normalizeActive()

    expect(settings.activeProviderID.isEmpty, "clears active provider when no provider is enabled")
    expect(settings.activeModel.isEmpty, "clears active model when no provider is enabled")
}

func testCloudSettingsPayloadPreservesRoutingPreferenceAndNormalizesModel() {
    let source = AppSettings()
    var provider = AIProvider(name: "Primary", apiProtocol: .openAI,
                              baseURL: "https://primary.test/v1",
                              apiKey: "sk-cloud-secret-abcdefghijklmnopqrstuvwxyz",
                              models: [
                                AIModelEntry(name: "disabled-active", enabled: false),
                                AIModelEntry(name: "enabled-model", enabled: true)
                              ])
    provider.isEnabled = true
    source.providers = [provider]
    source.activeProviderID = provider.id
    source.activeModel = "disabled-active"
    source.routingPreference = .quality
    source.historyContentStorage = .metadataOnly
    source.temperature = 3.5
    source.askPrompt = String(repeating: "a", count: AppSettings.importedPromptLimit + 25)
    source.translatePrompt = AppSettings.oldDefaultTranslatePrompt
    source.systemPrompt = " \n"
    let validRule = PrivacyRedactionRule(name: "数字", pattern: #"\d+"#, replacement: "[数字]")
    let invalidRule = PrivacyRedactionRule(name: "坏规则", pattern: "(", replacement: "[坏]")
    source.redactionRules = [validRule, invalidRule]
    let longCloudContext = String(repeating: "云", count: AppSettings.importedContextContentLimit + 25)
    let cloudProfile = ContextProfile(name: "Cloud", content: longCloudContext, isEnabled: true)
    source.contextProfiles = [cloudProfile]
    source.activeContextProfileID = cloudProfile.id

    guard let data = try? JSONEncoder().encode(CloudSettingsPayload(settings: source)),
          let decoded = try? JSONDecoder().decode(CloudSettingsPayload.self, from: data),
          let json = String(data: data, encoding: .utf8) else {
        expect(false, "cloud settings payload encode/decode succeeds")
        return
    }

    let target = AppSettings()
    decoded.apply(to: target)

    expect(CloudSettingsPayload(settings: source).providers.first?.apiKey == "",
           "cloud payload strips provider api key before encoding")
    expect(!json.contains("\"apiKey\""), "cloud payload omits apiKey field")
    expect(!json.contains(provider.apiKey), "cloud payload omits provider api key value")
    expect(decoded.providers.first?.apiKey == "", "cloud payload decodes with empty api key")
    expect(target.providers.first?.apiKey == "", "cloud payload apply does not introduce payload api key")
    expect(target.routingPreference == .quality, "cloud payload preserves routing preference")
    expect(target.historyContentStorage == .metadataOnly, "cloud payload preserves history content storage preference")
    expect(target.activeModel == "enabled-model", "cloud payload normalizes disabled active model on apply")
    expect(target.temperature == 1, "cloud payload clamps imported temperature")
    expect(decoded.askPrompt.count == AppSettings.importedPromptLimit,
           "cloud payload caps ask prompts before syncing")
    expect(decoded.translatePrompt == AppSettings.defaultTranslatePrompt,
           "cloud payload migrates the old translate prompt")
    expect(decoded.systemPrompt == "",
           "cloud payload preserves intentionally blank system prompts")
    expect(target.askPrompt.count == AppSettings.importedPromptLimit,
           "cloud payload applies capped ask prompts")
    expect(target.translatePrompt == AppSettings.defaultTranslatePrompt,
           "cloud payload applies migrated translate prompts")
    expect(target.systemPrompt == "",
           "cloud payload applies blank system prompts")
    expect(target.redactionRules.count == 1 && target.redactionRules.first?.pattern == #"\d+"#,
           "cloud payload drops invalid redaction rules")
    expect(target.contextProfiles.first?.content.count == AppSettings.importedContextContentLimit,
           "cloud payload caps context profile content")
    expect(target.activeContextProfileID == target.contextProfiles.first?.id,
           "cloud payload preserves usable active context after sanitizing")
}

func testCloudSettingsPayloadRemapsActiveProviderAfterProviderIDRepair() {
    let source = AppSettings()
    var firstProvider = AIProvider(name: "First", apiProtocol: .openAI,
                                   baseURL: "https://first.test/v1",
                                   apiKey: "first-secret",
                                   models: [AIModelEntry(name: "first-model")])
    firstProvider.id = "cloud-duplicate-provider"
    var secondProvider = AIProvider(name: "Second", apiProtocol: .openAI,
                                    baseURL: "https://second.test/v1",
                                    apiKey: "second-secret",
                                    models: [AIModelEntry(name: "second-model")])
    secondProvider.id = "cloud-duplicate-provider"
    source.providers = [firstProvider, secondProvider]
    source.activeProviderID = "cloud-duplicate-provider"
    source.activeModel = " second-model "
    var action = AIAction(name: "Cloud Override", prompt: "{{text}}")
    action.providerID = "cloud-duplicate-provider"
    action.modelOverride = " second-model "
    var invalidModelAction = AIAction(name: "Cloud Invalid Override", prompt: "{{text}}")
    invalidModelAction.providerID = "cloud-duplicate-provider"
    invalidModelAction.modelOverride = "missing-model"
    source.actions = [action, invalidModelAction]

    guard let data = try? JSONEncoder().encode(CloudSettingsPayload(settings: source)),
          let payload = try? JSONDecoder().decode(CloudSettingsPayload.self, from: data) else {
        expect(false, "cloud duplicate provider payload encode/decode succeeds")
        return
    }

    let target = AppSettings()
    payload.apply(to: target)

    expect(target.providers.count == 2,
           "cloud payload keeps duplicate-id providers after repairing ids")
    expect(Set(target.providers.map(\.id)).count == target.providers.count,
           "cloud payload repairs duplicate provider ids")
    expect(target.activeProviderID == target.providers[1].id,
           "cloud payload remaps active provider to the repaired duplicate id when its model matches")
    expect(target.activeProviderID != "cloud-duplicate-provider",
           "cloud payload active provider uses the repaired duplicate id")
    expect(target.activeModel == "second-model",
           "cloud payload trims active model names before normalization")
    expect(target.model == "second-model",
           "cloud payload keeps the active model available after provider id repair")
    expect(target.actions.first?.providerID == target.providers[1].id,
           "cloud payload remaps action provider override to the repaired duplicate provider id")
    expect(target.actions.first?.modelOverride == "second-model",
           "cloud payload trims action model overrides before provider mapping")
    expect(target.actions.dropFirst().first?.providerID == target.providers.first?.id,
           "cloud payload keeps provider override when model override is invalid")
    expect(target.actions.dropFirst().first?.modelOverride == nil,
           "cloud payload clears invalid action model overrides after provider mapping")
}

func testCloudSettingsPayloadDecodeRemapsActionsAfterProviderIDRepair() {
    let json = #"""
    {
      "providers": [
        {
          "id": "cloud-duplicate-provider",
          "name": "First",
          "apiProtocol": "OpenAI 兼容",
          "baseURL": "https://first.test/v1",
          "models": [
            { "name": "first-model", "enabled": true }
          ],
          "isEnabled": true
        },
        {
          "id": "cloud-duplicate-provider",
          "name": "Second",
          "apiProtocol": "OpenAI 兼容",
          "baseURL": "https://second.test/v1",
          "models": [
            { "name": "second-model", "enabled": true }
          ],
          "isEnabled": true
        }
      ],
      "activeProviderID": "cloud-duplicate-provider",
      "activeModel": " second-model ",
      "actions": [
        {
          "id": "cloud-action",
          "name": "Cloud Override",
          "prompt": "{{text}}",
          "providerID": " cloud-duplicate-provider ",
          "modelOverride": " second-model "
        }
      ]
    }
    """#
    guard let data = json.data(using: .utf8),
          let payload = try? JSONDecoder().decode(CloudSettingsPayload.self, from: data) else {
        expect(false, "cloud payload decodes raw duplicate provider json")
        return
    }

    expect(payload.providers.count == 2,
           "cloud payload decode keeps duplicate-id providers after repairing ids")
    expect(Set(payload.providers.map(\.id)).count == payload.providers.count,
           "cloud payload decode repairs duplicate provider ids")
    expect(payload.activeProviderID == payload.providers[1].id,
           "cloud payload decode remaps active provider to the repaired duplicate id")
    expect(payload.activeModel == "second-model",
           "cloud payload decode trims active model names")
    expect(payload.actions.first?.providerID == payload.providers[1].id,
           "cloud payload decode remaps action provider override to the repaired duplicate id")
    expect(payload.actions.first?.modelOverride == "second-model",
           "cloud payload decode trims action model override before mapping")
}

func testWorkModePresetsApplyCoherentSettings() {
    let settings = AppSettings()

    settings.applyWorkMode(.privacy)
    expect(settings.workModePreset == .privacy, "privacy mode is recorded as the last applied preset")
    expect(settings.privacyPreviewEnabled, "privacy mode enables submission preview")
    expect(settings.redactionEnabled, "privacy mode enables local redaction")
    expect(settings.historyContentStorage == .metadataOnly, "privacy mode stores history metadata only")
    expect(settings.autoRouteEnabled, "privacy mode keeps automatic routing available")
    expect(settings.fallbackEnabled, "privacy mode keeps fallback enabled")
    expect(settings.routingPreference == .balanced, "privacy mode keeps balanced routing")
    expect(settings.matchingWorkModePreset == .privacy, "privacy mode can be inferred from current behavior")
    expect(settings.workModeStatusTitle == "隐私模式", "work mode status names the matched preset")

    settings.redactionEnabled = false
    expect(settings.matchingWorkModePreset == nil, "manual changes can make the current behavior custom")
    expect(settings.workModeStatusTitle == "自定义模式", "work mode status reports custom behavior")
    expect(settings.workModeStatusDetail.contains("偏离预设"), "custom work mode explains the mismatch")

    settings.applyWorkMode(.speed)
    expect(settings.matchingWorkModePreset == .speed, "speed mode can be inferred from current behavior")
    expect(settings.routingPreference == .fastest, "speed mode selects fastest routing")
    expect(settings.historyContentStorage == .full, "speed mode keeps full history")
    expect(!settings.privacyPreviewEnabled, "speed mode avoids extra preview confirmation")
    expect(!settings.redactionEnabled, "speed mode avoids redaction overhead")

    settings.applyWorkMode(.quality)
    expect(settings.matchingWorkModePreset == .quality, "quality mode can be inferred from current behavior")
    expect(settings.autoRouteEnabled, "quality mode enables automatic routing")
    expect(settings.routingPreference == .quality, "quality mode selects quality routing")

    guard let encoded = try? JSONEncoder().encode(settings),
          let decoded = try? JSONDecoder().decode(AppSettings.self, from: encoded) else {
        expect(false, "work mode settings round-trip through AppSettings codable")
        return
    }
    expect(decoded.workModePreset == .quality, "AppSettings codable preserves last applied work mode")
    expect(decoded.matchingWorkModePreset == .quality, "AppSettings codable preserves coherent work mode behavior")

    let payload = CloudSettingsPayload(settings: settings)
    guard let payloadData = try? JSONEncoder().encode(payload),
          let decodedPayload = try? JSONDecoder().decode(CloudSettingsPayload.self, from: payloadData) else {
        expect(false, "work mode settings round-trip through iCloud payload")
        return
    }
    let synced = AppSettings()
    decodedPayload.apply(to: synced)
    expect(synced.workModePreset == .quality, "iCloud payload preserves last applied work mode")
    expect(synced.matchingWorkModePreset == .quality, "iCloud payload applies coherent work mode behavior")
}

func testWorkModeCommandFactoryReflectsCurrentState() {
    let descriptors = WorkModeCommandFactory.descriptors(current: .privacy)
    expect(descriptors.count == WorkModePreset.allCases.count, "work mode command factory exposes every preset")
    expect(descriptors.map(\.id).count == Set(descriptors.map(\.id)).count,
           "work mode command ids are unique")
    expect(descriptors.first(where: { $0.action == .apply(.privacy) })?.subtitle.hasPrefix("当前 - ") == true,
           "work mode command marks the current preset")
    expect(descriptors.first(where: { $0.action == .apply(.speed) })?.keywords.contains("低延迟") == true,
           "work mode command keywords include preset intent")
    expect(descriptors.first(where: { $0.action == .apply(.quality) })?.title == "切换到质量模式",
           "work mode command titles are user-facing")
}

func testSettingsToggleCommandReflectsCurrentState() {
    let settings = AppSettings()
    settings.privacyPreviewEnabled = false
    settings.redactionEnabled = true
    settings.historyContentStorage = .full
    settings.autoRouteEnabled = false
    settings.fallbackEnabled = true

    expect(SettingsToggleCommand.privacyPreview.title(isEnabled: SettingsToggleCommand.privacyPreview.isEnabled(in: settings)) == "开启发送前预览",
           "privacy preview command opens disabled feature")
    expect(SettingsToggleCommand.redaction.title(isEnabled: SettingsToggleCommand.redaction.isEnabled(in: settings)) == "关闭本地脱敏",
           "redaction command closes enabled feature")
    expect(SettingsToggleCommand.historyMetadataOnly.title(isEnabled: SettingsToggleCommand.historyMetadataOnly.isEnabled(in: settings)) == "开启历史仅元信息",
           "history metadata command opens full history storage")
    expect(SettingsToggleCommand.autoRoute.subtitle(isEnabled: SettingsToggleCommand.autoRoute.isEnabled(in: settings)).contains("当前已关闭"),
           "auto route subtitle reflects disabled state")
    expect(SettingsToggleCommand.fallback.subtitle(isEnabled: SettingsToggleCommand.fallback.isEnabled(in: settings)).contains("当前已开启"),
           "fallback subtitle reflects enabled state")
    expect(SettingsToggleCommand.allCases.map(\.id).count == Set(SettingsToggleCommand.allCases.map(\.id)).count,
           "toggle commands use unique ids")
}

func testSettingsToggleCommandResolvesAliasesAndSetsState() {
    let settings = AppSettings()
    settings.privacyPreviewEnabled = false
    settings.redactionEnabled = false
    settings.historyContentStorage = .full
    settings.autoRouteEnabled = false
    settings.fallbackEnabled = true

    expect(SettingsToggleCommand.resolve("privacy-preview") == .privacyPreview,
           "resolves privacy preview alias")
    expect(SettingsToggleCommand.resolve("privacy_preview") == .privacyPreview,
           "resolves underscore privacy preview alias")
    expect(SettingsToggleCommand.resolve("toggle_privacy_preview") == .privacyPreview,
           "resolves underscore stable privacy preview id")
    expect(SettingsToggleCommand.resolve("脱敏") == .redaction,
           "resolves redaction Chinese alias")
    expect(SettingsToggleCommand.resolve("local redaction") == .redaction,
           "resolves spaced local redaction alias")
    expect(SettingsToggleCommand.resolve("history metadata") == .historyMetadataOnly,
           "resolves spaced history metadata alias")
    expect(SettingsToggleCommand.resolve("toggle_history_metadata") == .historyMetadataOnly,
           "resolves underscore stable history metadata id")
    expect(SettingsToggleCommand.resolve("仅元信息") == .historyMetadataOnly,
           "resolves Chinese metadata-only history alias")
    expect(SettingsToggleCommand.resolve("route") == .autoRoute,
           "resolves auto route alias")
    expect(SettingsToggleCommand.resolve("auto route") == .autoRoute,
           "resolves spaced auto route alias")
    expect(SettingsToggleCommand.resolve("toggle_auto_route") == .autoRoute,
           "resolves underscore stable auto route id")
    expect(SettingsToggleCommand.resolve("failover") == .fallback,
           "resolves fallback alias")
    expect(SettingsToggleCommand.resolve("fail over") == .fallback,
           "resolves spaced fallback alias")
    expect(SettingsToggleCommand.resolve("backup_model") == .fallback,
           "resolves underscore backup model alias")
    expect(SettingsToggleCommand.resolve("missing") == nil,
           "rejects unknown toggle command")

    SettingsToggleCommand.privacyPreview.setEnabled(true, in: settings)
    SettingsToggleCommand.redaction.setEnabled(true, in: settings)
    SettingsToggleCommand.historyMetadataOnly.setEnabled(true, in: settings)
    SettingsToggleCommand.autoRoute.setEnabled(true, in: settings)
    SettingsToggleCommand.fallback.setEnabled(false, in: settings)

    expect(settings.privacyPreviewEnabled, "sets privacy preview state")
    expect(settings.redactionEnabled, "sets redaction state")
    expect(settings.historyContentStorage == .metadataOnly, "sets history metadata-only state")
    expect(settings.autoRouteEnabled, "sets auto route state")
    expect(!settings.fallbackEnabled, "sets fallback state")

    SettingsToggleCommand.historyMetadataOnly.setEnabled(false, in: settings)
    expect(settings.historyContentStorage == .full, "restores full history storage state")
}

func testSettingsWindowPinCommandReflectsCurrentState() {
    expect(SettingsWindowPinCommand.title(isPinned: false) == "置顶设置窗口",
           "unpinned settings window command pins the window")
    expect(SettingsWindowPinCommand.subtitle(isPinned: false).contains("保持在其他窗口上方"),
           "unpinned settings window subtitle explains pin behavior")
    expect(SettingsWindowPinCommand.systemImage(isPinned: false) == "pin.fill",
           "unpinned settings window command uses filled pin")
    expect(SettingsWindowPinCommand.statusSystemImage(isPinned: false) == "pin",
           "unpinned settings window status uses outline pin")
    expect(SettingsWindowPinCommand.accessibilityValue(isPinned: false) == "未置顶",
           "unpinned settings window status has an explicit accessibility value")

    expect(SettingsWindowPinCommand.title(isPinned: true) == "取消置顶设置窗口",
           "pinned settings window command unpins the window")
    expect(SettingsWindowPinCommand.subtitle(isPinned: true).contains("当前设置窗口"),
           "pinned settings window subtitle explains current state")
    expect(SettingsWindowPinCommand.systemImage(isPinned: true) == "pin.slash",
           "pinned settings window command uses slash pin")
    expect(SettingsWindowPinCommand.statusSystemImage(isPinned: true) == "pin.fill",
           "pinned settings window status uses filled pin")
    expect(SettingsWindowPinCommand.accessibilityValue(isPinned: true) == "已置顶",
           "pinned settings window status has an explicit accessibility value")
    expect(SettingsWindowPinCommand.keywords.contains("置顶"), "pin command is searchable in Chinese")
}

func testResultPinCommandReflectsCurrentState() {
    expect(ResultPinCommand.title(isPinned: false) == "固定结果窗",
           "unpinned result window command pins the result panel")
    expect(ResultPinCommand.subtitle(isPinned: false).contains("继续追问"),
           "unpinned result window subtitle explains follow-up behavior")
    expect(ResultPinCommand.systemImage(isPinned: false) == "pin.fill",
           "unpinned result window command uses filled pin")

    expect(ResultPinCommand.title(isPinned: true) == "取消固定结果窗",
           "pinned result window command unpins the result panel")
    expect(ResultPinCommand.subtitle(isPinned: true).contains("保持打开"),
           "pinned result window subtitle explains current state")
    expect(ResultPinCommand.systemImage(isPinned: true) == "pin.slash",
           "pinned result window command uses slash pin")
    expect(ResultPinCommand.statusTitle == "已固定",
           "pinned result window status badge has stable title")
    expect(ResultPinCommand.statusSystemImage == "pin.fill",
           "pinned result window status badge uses filled pin")
    expect(ResultPinCommand.keywords.contains("结果"), "result pin command is searchable in Chinese")
    expect(ResultPinCommand.keyEquivalent == "p", "result pin command keeps p shortcut")
    expect(ResultPinCommand.modifiers == [.command, .shift],
           "result pin command keeps command-shift shortcut")
    expect(ResultPinCommand.shortcutText == "⌘⇧P", "result pin command exposes display shortcut")
}

func testDisplayBehaviorCommandFactoryReflectsCurrentState() {
    let descriptors = DisplayBehaviorCommandFactory.descriptors(showDockIcon: true,
                                                                loginItemEnabled: false,
                                                                typewriterSpeed: .normal)

    expect(descriptors.count == 2 + TypewriterSpeed.allCases.count,
           "display behavior commands include dock, login item, and typewriter speeds")
    expect(descriptors[0].id == "dock-icon-toggle", "dock command is first")
    expect(descriptors[0].title == "隐藏 Dock 图标", "dock command reflects visible state")
    expect(descriptors[0].action == .setDockIcon(false), "dock command toggles off")
    expect(descriptors[1].title == "开启开机启动", "login item command reflects disabled state")
    expect(descriptors[1].action == .setLoginItem(true), "login item command toggles on")

    guard let currentSpeed = descriptors.first(where: { $0.action == .setTypewriterSpeed(.normal) }),
          let fastSpeed = descriptors.first(where: { $0.action == .setTypewriterSpeed(.fast) }) else {
        expect(false, "typewriter speed commands exist")
        return
    }
    expect(currentSpeed.subtitle == "当前速度", "current typewriter speed is marked")
    expect(currentSpeed.systemImage == "checkmark.circle.fill", "current typewriter speed uses check icon")
    expect(fastSpeed.subtitle == "更快地显示流式结果", "non-current speed explains behavior")
    expect(fastSpeed.systemImage == "text.cursor", "non-current speed uses text cursor icon")
}

func testRoutingContextCommandFactoryReflectsCurrentState() {
    let routing = RoutingContextCommandFactory.routingDescriptors(current: .quality)
    expect(routing.count == AIRoutingPreference.allCases.count, "routing command includes all preferences")
    expect(routing.first(where: { $0.action == .setRoutingPreference(.quality) })?.subtitle.hasPrefix("当前 - ") == true,
           "current routing preference is marked")
    expect(routing.first(where: { $0.action == .setRoutingPreference(.fastest) })?.systemImage == "point.3.connected.trianglepath.dotted",
           "non-current routing preference uses route icon")

    let enabled = ContextProfile(id: "project-a",
                                 name: "项目 A",
                                 content: "术语表",
                                 isEnabled: true)
    let disabled = ContextProfile(id: "project-b",
                                  name: "项目 B",
                                  content: "禁用",
                                  isEnabled: false)
    let empty = ContextProfile(id: "project-c",
                               name: "项目 C",
                               content: " \n ",
                               isEnabled: true)
    let contexts = RoutingContextCommandFactory.contextDescriptors(
        profiles: [enabled, disabled, empty],
        activeProfileID: enabled.id
    )

    expect(contexts.map(\.id) == ["context-clear", "context-copy-active", "context-copy-effective-prompt", "context-copy-status", "context-project-a"],
           "context command includes clear, copy, effective prompt, status and usable profiles only")
    expect(contexts[0].action == .clearContext, "clear command clears active context")
    expect(contexts[1].action == .copyActiveContext, "copy command copies active context")
    expect(contexts[1].subtitle == "项目 A", "copy command identifies active context profile")
    expect(contexts[1].keywords.contains("术语表"), "copy command is searchable by active context content")
    expect(contexts[2].action == .copyEffectiveSystemPrompt, "effective prompt command copies rendered system prompt")
    expect(contexts[2].subtitle == "全局 System Prompt + 当前上下文", "effective prompt command explains active context inclusion")
    expect(contexts[3].action == .copyContextStatus, "context status command copies safe metadata")
    expect(contexts[3].subtitle == "不包含上下文正文", "context status command explains safe metadata behavior")
    expect(contexts[4].subtitle == "当前上下文包", "active context profile is marked")
    expect(contexts[4].action == .setContextProfile(enabled.id), "context command switches by profile id")

    let noActive = RoutingContextCommandFactory.contextDescriptors(profiles: [enabled],
                                                                   activeProfileID: "")
    expect(noActive.map(\.id) == ["context-copy-effective-prompt", "context-copy-status", "context-project-a"],
           "clear and active context copy commands are hidden when no context is active")
    expect(noActive[0].subtitle == "全局 System Prompt", "effective prompt command explains base-only prompt")

    let slashID = ContextProfile(id: "team/A",
                                 name: "团队 A",
                                 content: "背景",
                                 isEnabled: true)
    let spaceID = ContextProfile(id: "team A",
                                 name: "团队 A 备份",
                                 content: "背景",
                                 isEnabled: true)
    let slugged = RoutingContextCommandFactory.contextDescriptors(profiles: [slashID, spaceID],
                                                                  activeProfileID: slashID.id)
    expect(slugged.map(\.id) == ["context-clear", "context-copy-active", "context-copy-effective-prompt", "context-copy-status", "context-team-A", "context-team-A-2"],
           "context command ids slug profile ids and disambiguate collisions")
    expect(slugged[4].action == .setContextProfile("team/A"),
           "context command action keeps original slash profile id")
    expect(slugged[5].action == .setContextProfile("team A"),
           "context command action keeps original spaced profile id")

    let unsafeProfile = ContextProfile(id: "unsafe",
                                       name: "项目\n# 注入|`A`",
                                       content: String(repeating: "上下文\n", count: 80),
                                       isEnabled: true)
    let unsafeContexts = RoutingContextCommandFactory.contextDescriptors(profiles: [unsafeProfile],
                                                                         activeProfileID: unsafeProfile.id)
    expect(unsafeContexts[1].subtitle == "项目 # 注入/'A'",
           "active context copy command keeps unsafe profile names single-line")
    expect(unsafeContexts[4].title == "切换上下文: 项目 # 注入/'A'",
           "context switch command title keeps unsafe profile names single-line")
    expect(unsafeContexts[4].action == .setContextProfile("unsafe"),
           "context switch command action keeps original profile id")
    expect(!unsafeContexts[4].title.contains("\n"), "context switch command title does not contain newlines")
    expect(unsafeContexts[1].keywords.contains("\n") == false &&
           unsafeContexts[1].keywords.contains("|") == false &&
           unsafeContexts[1].keywords.contains("`") == false,
           "active context copy command keywords are search-safe")
    expect(unsafeContexts[4].keywords.contains("\n") == false &&
           unsafeContexts[4].keywords.contains("|") == false &&
           unsafeContexts[4].keywords.contains("`") == false,
           "context switch command keywords are search-safe")
    expect(unsafeContexts[4].keywords.count < 420,
           "context command keywords cap long context content")
}

func testResultDiagnosticsCommandIsSearchable() {
    expect(ResultDiagnosticsCommand.briefTitle == "复制精简请求诊断", "brief result diagnostics command has clear title")
    expect(ResultDiagnosticsCommand.briefCompactTitle == "复制精简", "brief result diagnostics command has compact title")
    expect(ResultDiagnosticsCommand.briefSubtitle.contains("错误详情"), "brief result diagnostics subtitle explains omitted details")
    expect(ResultDiagnosticsCommand.briefSubtitle.contains("恢复建议"), "brief result diagnostics subtitle mentions recovery suggestions")
    expect(ResultDiagnosticsCommand.title == "复制完整请求诊断", "full result diagnostics command has clear title")
    expect(ResultDiagnosticsCommand.compactTitle == "复制完整", "full result diagnostics command has compact title")
    expect(ResultDiagnosticsCommand.subtitle.contains("fallback"), "result diagnostics subtitle mentions fallback")
    expect(ResultDiagnosticsCommand.subtitle.contains("恢复建议"), "result diagnostics subtitle mentions recovery suggestions")
    expect(ResultDiagnosticsCommand.subtitle.contains("隐私"), "result diagnostics subtitle mentions privacy")
    expect(ResultDiagnosticsCommand.systemImage == "point.3.connected.trianglepath.dotted",
           "result diagnostics command uses route-like symbol")
    expect(ResultDiagnosticsCommand.briefKeywords.contains("summary"), "brief result diagnostics command is searchable by summary")
    expect(ResultDiagnosticsCommand.briefKeywords.contains("recovery"), "brief result diagnostics command is searchable by recovery")
    expect(ResultDiagnosticsCommand.briefKeywords.contains("修复"), "brief result diagnostics command is searchable by Chinese recovery terms")
    expect(ResultDiagnosticsCommand.keywords.contains("route"), "result diagnostics command is searchable in English")
    expect(ResultDiagnosticsCommand.keywords.contains("privacy"), "result diagnostics command is searchable by privacy in English")
    expect(ResultDiagnosticsCommand.keywords.contains("api key"), "result diagnostics command is searchable by API key problems")
    expect(ResultDiagnosticsCommand.keywords.contains("无可用"), "result diagnostics command is searchable by unavailable-route symptoms")
    expect(ResultDiagnosticsCommand.keywords.contains("脱敏"), "result diagnostics command is searchable by redaction in Chinese")
    expect(ResultDiagnosticsCommand.keywords.contains("诊断"), "result diagnostics command is searchable in Chinese")
}

func testResultRecoveryCommandPointsToAISettings() {
    expect(ResultRecoveryCommand.openAISettingsTitle == "打开 AI 设置",
           "result recovery command has a clear AI settings title")
    expect(ResultRecoveryCommand.openAISettingsCompactTitle == "AI 设置",
           "result recovery command has a compact button title")
    expect(ResultRecoveryCommand.openAISettingsSubtitle.contains("API Key"),
           "result recovery command explains API key troubleshooting")
    expect(ResultRecoveryCommand.openAISettingsSubtitle.contains("Base URL"),
           "result recovery command explains endpoint troubleshooting")
    expect(ResultRecoveryCommand.openAISettingsSystemImage == "gearshape.2",
           "result recovery command uses a settings-like symbol")
    expect(ResultRecoveryCommand.openAISettingsKeywords.contains("api key"),
           "result recovery command is searchable by API key problems")
    expect(ResultRecoveryCommand.openAISettingsKeywords.contains("Base URL") == false,
           "result recovery command keeps searchable keywords lowercase where useful")
    expect(ResultRecoveryCommand.openAISettingsKeywords.contains("base url"),
           "result recovery command is searchable by endpoint problems")
    expect(ResultRecoveryCommand.openAISettingsKeywords.contains("修复"),
           "result recovery command is searchable by Chinese recovery terms")

    let missingProvider = ResultRecoveryCommand.openAISettingsDescriptor(recoveryCode: "missing-provider")
    expect(missingProvider.title == "添加 AI 供应商",
           "result recovery command points missing providers to provider setup")
    expect(missingProvider.compactTitle == "添加供应商",
           "missing provider recovery keeps a compact button label")
    expect(missingProvider.subtitle.contains("填写 API Key"),
           "missing provider recovery explains the setup checklist")
    expect(missingProvider.systemImage == "plus.circle",
           "missing provider recovery uses an add-like symbol")
    expect(missingProvider.keywords.contains("无可用"),
           "missing provider recovery is searchable by unavailable-route terms")

    let missingModel = ResultRecoveryCommand.openAISettingsDescriptor(recoveryCode: "missing-model")
    expect(missingModel.title == "选择可用模型",
           "result recovery command points missing models to model selection")
    expect(missingModel.compactTitle == "选择模型",
           "missing model recovery keeps a compact button label")
    expect(missingModel.subtitle.contains("设为当前模型"),
           "missing model recovery explains the current model requirement")
    expect(missingModel.systemImage == "checklist.checked",
           "missing model recovery uses a selection-like symbol")

    let apiKey = ResultRecoveryCommand.openAISettingsDescriptor(recoveryCode: "api-key")
    expect(apiKey.title == "填写 API Key",
           "result recovery command points authentication errors to API key setup")
    expect(apiKey.compactTitle == "API Key",
           "API key recovery keeps a compact button label")
    expect(apiKey.systemImage == "key",
           "API key recovery uses a key symbol")

    let modelNotFound = ResultRecoveryCommand.openAISettingsDescriptor(recoveryCode: "model-not-found")
    expect(modelNotFound.title == "检查模型名称",
           "result recovery command points model lookup failures to model names")
    expect(modelNotFound.compactTitle == "模型名称",
           "model lookup recovery keeps a compact button label")

    let configurationRetry = ResultRecoveryCommand.retryDescriptor(recoveryCode: "api-key")
    expect(configurationRetry.title == "配置后重试",
           "configuration failures ask users to retry after fixing settings")
    expect(configurationRetry.compactTitle == "配置后重试",
           "configuration retry keeps a compact button label")
    expect(configurationRetry.subtitle.contains("AI 设置"),
           "configuration retry explains the required setup step")
    expect(configurationRetry.systemImage == "arrow.clockwise.circle",
           "configuration retry uses a retry-with-context symbol")

    let contextRetry = ResultRecoveryCommand.retryDescriptor(recoveryCode: "context-limit")
    expect(contextRetry.title == "调整后重试",
           "content-shape failures ask users to adjust payload before retrying")
    expect(contextRetry.systemImage == "slider.horizontal.3",
           "content-shape retry uses an adjustment symbol")

    let rateLimitRetry = ResultRecoveryCommand.retryDescriptor(recoveryCode: "rate-limit")
    expect(rateLimitRetry.title == "稍后重试",
           "rate limit failures ask users to wait before retrying")
    expect(rateLimitRetry.systemImage == "timer",
           "rate limit retry uses a time symbol")

    let transientRetry = ResultRecoveryCommand.retryDescriptor(recoveryCode: "network")
    expect(transientRetry.title == "重试请求",
           "transient failures keep a direct retry affordance")
    expect(transientRetry.compactTitle == "重试",
           "transient retry keeps the shortest button label")

    expect(ResultRecoveryCommand.primaryAction(recoveryCode: "api-key") == .settings,
           "configuration failures prefer opening AI settings before retrying")
    expect(ResultRecoveryCommand.primaryAction(recoveryCode: "missing-model") == .settings,
           "missing model failures prefer opening AI settings before retrying")
    expect(ResultRecoveryCommand.primaryAction(recoveryCode: "model-not-found") == .settings,
           "model lookup failures prefer checking model settings before retrying")
    expect(ResultRecoveryCommand.primaryAction(recoveryCode: "context-limit") == .retry,
           "payload adjustment failures prefer the adjusted retry action before generic settings")
    expect(ResultRecoveryCommand.primaryAction(recoveryCode: "payload-too-large") == .retry,
           "large payload failures prefer the adjusted retry action before generic settings")
    expect(ResultRecoveryCommand.primaryAction(recoveryCode: "generic-failure") == .retry,
           "unknown request failures prefer retry before generic settings")
    expect(ResultRecoveryCommand.primaryAction(recoveryCode: nil) == .retry,
           "missing recovery codes keep retry first instead of implying settings are required")
    expect(ResultRecoveryCommand.primaryAction(recoveryCode: "network") == .retry,
           "transient network failures prefer retry first")
    expect(ResultRecoveryCommand.primaryAction(recoveryCode: "provider-service") == .retry,
           "transient provider service failures prefer retry first")
    expect(ResultRecoveryCommand.primaryAction(recoveryCode: "rate-limit") == .retry,
           "rate-limit failures keep retry visible first after waiting")
}

func testFollowUpInputBehaviorSupportsMultilineDrafts() {
    expect(FollowUpInputBehavior.placeholder == "追问…",
           "follow-up input keeps a concise placeholder")
    expect(FollowUpInputBehavior.accessibilityLabel == "追问输入框",
           "follow-up input exposes a clear accessibility label")
    expect(FollowUpInputBehavior.helpText.contains("Return 发送追问"),
           "follow-up input help explains submit behavior")
    expect(FollowUpInputBehavior.helpText.contains("Shift+Return"),
           "follow-up input help explains shift return newline behavior")
    expect(FollowUpInputBehavior.helpText.contains("Option+Return"),
           "follow-up input help explains option return newline behavior")
    expect(FollowUpInputBehavior.minHeight >= 30,
           "follow-up input has enough height for comfortable text editing")
    expect(FollowUpInputBehavior.maxHeight > FollowUpInputBehavior.minHeight,
           "follow-up input can grow for multiline drafts")
    expect(FollowUpInputBehavior.returnKeyBehavior(shift: false,
                                                   option: false) == .submit,
           "plain Return submits the follow-up")
    expect(FollowUpInputBehavior.returnKeyBehavior(shift: true,
                                                   option: false) == .insertNewline,
           "Shift-Return inserts a newline in multiline follow-up drafts")
    expect(FollowUpInputBehavior.returnKeyBehavior(shift: false,
                                                   option: true) == .insertNewline,
           "Option-Return inserts a newline in multiline follow-up drafts")
    expect(FollowUpInputBehavior.shouldBrowseHistory(currentText: ""),
           "empty follow-up draft can browse history with arrow keys")
    expect(FollowUpInputBehavior.shouldBrowseHistory(currentText: " \n\t "),
           "whitespace-only follow-up draft can browse history with arrow keys")
    expect(!FollowUpInputBehavior.shouldBrowseHistory(currentText: "继续解释"),
           "non-empty follow-up draft keeps arrow keys for text navigation")
    expect(!FollowUpInputBehavior.shouldBrowseHistory(currentText: "第一行\n第二行"),
           "multiline follow-up draft keeps arrow keys for text navigation")
}

func testFollowUpHistoryStoreNavigatesRecentPromptsSafely() {
    var history = FollowUpHistoryStore(limit: 3)
    expect(history.count == 0, "follow-up history starts empty")
    expect(history.previous() == nil, "empty follow-up history has no previous entry")
    expect(history.next() == nil, "empty follow-up history has no next entry")
    expect(!history.shouldHandleNavigation(currentText: "", direction: .up),
           "empty follow-up history does not intercept up navigation")
    expect(!history.shouldHandleNavigation(currentText: "", direction: .down),
           "empty follow-up history does not intercept down navigation")

    history.record(" 第一条 ")
    history.record("第二条")
    history.record("第三条")
    history.record("第二条")
    expect(history.entries == ["第一条", "第三条", "第二条"],
           "follow-up history deduplicates prompts and moves repeated prompts to the newest position")
    expect(history.count == 3, "follow-up history reports bounded count")

    history.record("第四条")
    expect(history.entries == ["第三条", "第二条", "第四条"],
           "follow-up history keeps only the most recent bounded entries")
    history.record(" \n\t ")
    expect(history.entries == ["第三条", "第二条", "第四条"],
           "follow-up history ignores blank prompts")

    expect(history.shouldHandleNavigation(currentText: "", direction: .up),
           "blank draft can start history navigation with up")
    expect(!history.shouldHandleNavigation(currentText: "", direction: .down),
           "blank draft does not intercept down when no history entry is selected")
    expect(history.previous() == "第四条",
           "first history-up selects the newest prompt")
    expect(history.shouldHandleNavigation(currentText: "第四条", direction: .up),
           "selected history text continues handling up navigation")
    expect(history.shouldHandleNavigation(currentText: "第四条", direction: .down),
           "selected history text continues handling down navigation")
    expect(!history.shouldHandleNavigation(currentText: "第四条 edited", direction: .up),
           "edited history text returns arrow keys to text navigation")
    expect(history.previous() == "第二条",
           "repeated history-up walks to older prompts")
    expect(history.previous() == "第三条",
           "history-up can reach the oldest retained prompt")
    expect(history.previous() == "第三条",
           "history-up stays at the oldest retained prompt")
    expect(history.next() == "第二条",
           "history-down walks toward newer prompts")
    expect(history.next() == "第四条",
           "history-down reaches the newest prompt")
    expect(history.next() == "",
           "history-down from the newest prompt clears back to an empty draft")
    expect(!history.shouldHandleNavigation(currentText: "第四条", direction: .down),
           "cleared history navigation no longer treats old selected text as active")

    history.record("第五条")
    expect(history.selectedText == nil,
           "recording a new prompt resets history navigation")
    expect(history.entries == ["第二条", "第四条", "第五条"],
           "recording a new prompt still enforces the history limit")

    var longHistory = FollowUpHistoryStore(limit: 2)
    let longPrompt = String(repeating: "长", count: FollowUpHistoryStore.maxEntryCharacters + 20)
    longHistory.record(longPrompt)
    expect(longHistory.entries.count == 1,
           "follow-up history stores long prompts as a single bounded entry")
    expect(longHistory.entries[0].count == FollowUpHistoryStore.maxEntryCharacters,
           "follow-up history caps oversized prompt history entries")
    expect(longHistory.entries[0].hasSuffix("..."),
           "follow-up history marks truncated prompt history entries")
    expect(!longHistory.entries[0].contains(String(repeating: "长", count: FollowUpHistoryStore.maxEntryCharacters + 1)),
           "follow-up history drops far-tail content from oversized prompts")
    longHistory.record(longPrompt)
    expect(longHistory.entries.count == 1,
           "follow-up history deduplicates repeated oversized prompts after truncation")
    expect(longHistory.previous() == longHistory.entries[0],
           "follow-up history returns the bounded oversized entry when navigating")

    var zeroLimitHistory = FollowUpHistoryStore(limit: 0)
    expect(zeroLimitHistory.effectiveLimit == 1,
           "follow-up history clamps zero limit to one retained prompt")
    zeroLimitHistory.record("一")
    zeroLimitHistory.record("二")
    expect(zeroLimitHistory.entries == ["二"],
           "follow-up history with zero configured limit still keeps the latest prompt")

    var negativeLimitHistory = FollowUpHistoryStore(limit: -5)
    expect(negativeLimitHistory.effectiveLimit == 1,
           "follow-up history clamps negative limits to one retained prompt")
    negativeLimitHistory.record("旧")
    negativeLimitHistory.record("新")
    expect(negativeLimitHistory.entries == ["新"],
           "follow-up history with negative configured limit still keeps the latest prompt")
}

func testResultCommandFactoryHidesCommandsWithoutResultContext() {
    let descriptors = ResultCommandFactory.descriptors(hasResult: false,
                                                       hasDiagnostics: false,
                                                       canWriteBack: false,
                                                       isStreaming: false,
                                                       hasSourceText: false)
    expect(descriptors.isEmpty, "empty result panel contributes no result commands")
}

func testResultCommandStateBuildsFromResultTexts() {
    let ready = ResultCommandState(resultText: "结果",
                                   diagnosticsText: "route ok",
                                   isStreaming: false,
                                   sourceText: "原文")
    expect(ready == ResultCommandState(hasResult: true,
                                       hasDiagnostics: true,
                                       canWriteBack: true,
                                       isStreaming: false,
                                       hasSourceText: true),
           "result command state derives ready state from result texts")

    let streaming = ResultCommandState(resultText: "partial",
                                       diagnosticsText: "",
                                       isStreaming: true,
                                       sourceText: "原文",
                                       protectsContentExport: true)
    expect(streaming.hasResult, "streaming state can still have partial result text")
    expect(!streaming.hasDiagnostics, "blank diagnostics text disables diagnostics")
    expect(!streaming.canWriteBack, "streaming result cannot write back")
    expect(streaming.hasSourceText, "non-empty source enables regenerate after streaming")
    expect(streaming.protectsContentExport, "result command state carries protected export state")
}

func testResultCommandFactoryBuildsStableMenuCommands() {
    let descriptors = ResultCommandFactory.menuDescriptors()
    expect(descriptors.map(\.id) == [
        "result-menu-copy",
        "result-menu-copy-markdown",
        "result-menu-copy-brief-diagnostics",
        "result-menu-copy-diagnostics",
        "result-menu-open-ai-settings",
        "result-menu-replace",
        "result-menu-append",
        "result-menu-export",
        "result-menu-regenerate",
        "result-menu-stop"
    ], "result menu commands keep stable desktop menu order")
    expect(descriptors.map(\.action) == [
        .copyOutput,
        .copyMarkdown,
        .copyBriefDiagnostics,
        .copyDiagnostics,
        .openAISettings,
        .replaceOriginal,
        .appendToDocument,
        .exportConversation,
        .regenerate,
        .stop
    ], "result menu commands carry expected actions")
    expect(descriptors[0].title == "复制结果" &&
           descriptors[0].keyEquivalent == "c" &&
           descriptors[0].modifiers == [.command, .shift],
           "copy result menu command keeps its shortcut")
    expect(descriptors[1].modifiers == [.command, .option],
           "copy markdown menu command keeps command-option shortcut")
    expect(descriptors[2].title == ResultDiagnosticsCommand.briefTitle &&
           descriptors[2].keyEquivalent == "d" &&
           descriptors[2].modifiers == [.command, .shift],
           "brief diagnostics menu command keeps command-shift shortcut")
    expect(descriptors[3].title == ResultDiagnosticsCommand.title &&
           descriptors[3].keyEquivalent == "d" &&
           descriptors[3].modifiers == [.command, .option],
           "full diagnostics menu command keeps command-option shortcut")
    expect(descriptors[4].title == ResultRecoveryCommand.openAISettingsTitle &&
           descriptors[4].keyEquivalent.isEmpty &&
           descriptors[4].modifiers.isEmpty,
           "open AI settings menu command has no direct shortcut")
    expect(descriptors[6].keyEquivalent == "\r" &&
           descriptors[6].modifiers == [.command, .shift],
           "append menu command keeps command-shift-return shortcut")
    expect(descriptors[7].title == "导出对话…",
           "export menu command keeps menu ellipsis")
    expect(descriptors[9].keyEquivalent == "\u{1b}" && descriptors[9].modifiers.isEmpty,
           "stop menu command keeps escape shortcut")
    expect(ResultCommandFactory.descriptor(for: .copyOutput).systemImage == "doc.on.doc",
           "copy output descriptor carries shared icon")
    expect(ResultCommandFactory.descriptor(for: .appendToDocument).title == "追加到文档",
           "append descriptor carries shared title")
    expect(ResultCommandFactory.shortcutText(for: .copyMarkdown) == "⌘⌥C",
           "copy markdown shortcut text is displayable")
    expect(ResultCommandFactory.shortcutText(for: .copyBriefDiagnostics) == "⌘⇧D",
           "brief diagnostics shortcut text is displayable")
    expect(ResultCommandFactory.shortcutText(for: .copyDiagnostics) == "⌘⌥D",
           "full diagnostics shortcut text is displayable")
    expect(ResultCommandFactory.shortcutText(for: .openAISettings) == nil,
           "open AI settings command intentionally has no shortcut")
    expect(ResultCommandFactory.shortcutText(for: .appendToDocument) == "⌘⇧↩",
           "append shortcut text handles return key")
    expect(ResultCommandFactory.shortcutText(for: .stop) == "Esc",
           "stop shortcut text handles escape")
    expect(ResultCommandFactory.helpText(for: .replaceOriginal) == "替换原文 (⌘↩)",
           "result command help combines title and shortcut")
}

func testResultCommandFactoryExplainsProtectedConversationExports() {
    let normalCopy = ResultCommandFactory.descriptor(for: .copyMarkdown)
    expect(normalCopy.subtitle == "Markdown,含原文、结果、模型和路由摘要",
           "normal copy markdown descriptor keeps its full-content subtitle")
    expect(ResultCommandFactory.helpText(for: .copyMarkdown) == "复制完整结果 (⌘⌥C)",
           "normal copy markdown help remains compact")

    let protectedState = ResultCommandState(hasResult: true,
                                            hasDiagnostics: true,
                                            canWriteBack: true,
                                            isStreaming: false,
                                            hasSourceText: true,
                                            protectsContentExport: true)
    let descriptors = ResultCommandFactory.descriptors(state: protectedState)
    let copyMarkdown = descriptors.first { $0.action == .copyMarkdown }
    let exportConversation = descriptors.first { $0.action == .exportConversation }

    expect(copyMarkdown?.subtitle == "高风险保护:Markdown 将省略原文和结果正文",
           "protected copy markdown descriptor explains omitted content")
    expect(copyMarkdown?.keywords.contains("隐私") == true &&
           copyMarkdown?.keywords.contains("省略") == true,
           "protected copy markdown descriptor is searchable by privacy protection")
    expect(exportConversation?.subtitle == "高风险保护:导出的 Markdown 将省略正文",
           "protected export descriptor explains omitted content")
    expect(exportConversation?.keywords.contains("privacy") == true &&
           exportConversation?.keywords.contains("保护") == true,
           "protected export descriptor is searchable by privacy protection")
    expect(ResultCommandFactory.helpText(for: .copyMarkdown, in: protectedState)
        == "复制完整结果: 高风险保护:Markdown 将省略原文和结果正文 (⌘⌥C)",
           "protected copy markdown help includes the protection warning")
    expect(ResultCommandFactory.helpText(for: .exportConversation, in: protectedState)
        == "导出对话: 高风险保护:导出的 Markdown 将省略正文 (⌘E)",
           "protected export help includes the protection warning")
    expect(ResultCommandFactory.helpText(for: .copyOutput, in: protectedState) == "复制结果 (⌘⇧C)",
           "protected export state does not change copy-output help")
    expect(ResultCommandFactory.menuTitle(for: .copyMarkdown, in: protectedState) == "复制完整结果 (省略正文)",
           "protected copy markdown menu title warns about omitted content")
    expect(ResultCommandFactory.menuTitle(for: .exportConversation, in: protectedState) == "导出对话… (省略正文)",
           "protected export menu title warns about omitted content")
    expect(ResultCommandFactory.menuTitle(for: .copyOutput, in: protectedState) == "复制结果",
           "protected export state does not change copy-output menu title")
    expect(ResultCommandFactory.menuToolTip(for: .copyMarkdown, in: protectedState)
        == "高风险保护:Markdown 将省略原文和结果正文",
           "protected copy markdown menu tooltip explains omitted content")
    expect(ResultCommandFactory.menuToolTip(for: .exportConversation, in: protectedState)
        == "高风险保护:导出的 Markdown 将省略正文",
           "protected export menu tooltip explains omitted content")
    expect(ResultCommandFactory.menuToolTip(for: .copyOutput, in: protectedState) == nil,
           "protected export state does not add copy-output tooltip")
    expect(ResultCommandFactory.accessibilityLabel(for: .copyMarkdown, in: protectedState)
        == "复制完整结果, 高风险保护:Markdown 将省略原文和结果正文",
           "protected copy markdown accessibility label includes omitted-content warning")
    expect(ResultCommandFactory.accessibilityLabel(for: .exportConversation, in: protectedState)
        == "导出对话, 高风险保护:导出的 Markdown 将省略正文",
           "protected export accessibility label includes omitted-content warning")
    expect(ResultCommandFactory.accessibilityLabel(for: .copyOutput, in: protectedState) == "复制结果",
           "protected export state does not change copy-output accessibility label")
}

func testResultCommandFactoryAdaptsAISettingsRecoveryCommand() {
    let missingProviderState = ResultCommandState(hasResult: false,
                                                  hasDiagnostics: true,
                                                  canWriteBack: false,
                                                  isStreaming: false,
                                                  hasSourceText: true,
                                                  recoveryCode: "missing-provider")
    let missingProvider = ResultCommandFactory.descriptors(state: missingProviderState)
        .first { $0.action == .openAISettings }
    expect(missingProvider?.title == "添加 AI 供应商",
           "result command palette uses recovery-specific provider setup title")
    expect(missingProvider?.subtitle.contains("配置可用模型") == true,
           "provider setup recovery explains the next setup step")
    expect(missingProvider?.systemImage == "plus.circle",
           "provider setup recovery command uses its recovery icon")
    expect(ResultCommandFactory.helpText(for: .openAISettings, in: missingProviderState) == "添加 AI 供应商",
           "recovery-specific AI settings command keeps help concise without a shortcut")
    expect(ResultCommandFactory.accessibilityLabel(for: .openAISettings, in: missingProviderState) == "添加 AI 供应商",
           "recovery-specific AI settings command exposes the adapted title to accessibility")
    expect(ResultCommandFactory.menuTitle(for: .openAISettings, in: missingProviderState) == "添加 AI 供应商",
           "result menu validation uses the adapted recovery title")
    expect(ResultCommandFactory.menuToolTip(for: .openAISettings, in: missingProviderState)?.contains("API Key") == true,
           "result menu tooltip explains provider recovery")

    let missingModelState = ResultCommandState(hasResult: false,
                                               hasDiagnostics: true,
                                               canWriteBack: false,
                                               isStreaming: false,
                                               hasSourceText: false,
                                               recoveryCode: "missing-model")
    let missingModel = ResultCommandFactory.descriptors(state: missingModelState)
        .first { $0.action == .openAISettings }
    expect(missingModel?.title == "选择可用模型",
           "result command palette uses recovery-specific model setup title")
    expect(missingModel?.keywords.contains("选择") == true,
           "model setup recovery command is searchable by the adapted action")
}

func testResultCommandFactoryAdaptsRetryRecoveryCommand() {
    let apiKeyState = ResultCommandState(hasResult: false,
                                         hasDiagnostics: true,
                                         canWriteBack: false,
                                         isStreaming: false,
                                         hasSourceText: true,
                                         recoveryCode: "api-key")
    let apiKeyRetry = ResultCommandFactory.descriptors(state: apiKeyState)
        .first { $0.action == .regenerate }
    let apiKeyCommands = ResultCommandFactory.descriptors(state: apiKeyState).map(\.action)
    expect(apiKeyCommands.prefix(2) == [.openAISettings, .copyBriefDiagnostics],
           "configuration recovery puts AI settings before retry in the command palette")
    expect(apiKeyCommands.last == .regenerate,
           "configuration recovery keeps retry available after diagnostics")
    expect(apiKeyRetry?.title == "配置后重试",
           "configuration failures adapt regenerate to a setup-first retry command")
    expect(apiKeyRetry?.subtitle == "先修复 AI 设置,再重新发送请求",
           "configuration retry explains why immediate retry may not help")
    expect(apiKeyRetry?.systemImage == "arrow.clockwise.circle",
           "configuration retry command uses its recovery icon")
    expect(ResultCommandFactory.helpText(for: .regenerate, in: apiKeyState) == "配置后重试 (⌘R)",
           "configuration retry keeps the existing regenerate shortcut")
    expect(ResultCommandFactory.accessibilityLabel(for: .regenerate, in: apiKeyState) == "配置后重试",
           "configuration retry exposes the adapted action to accessibility")
    expect(ResultCommandFactory.menuTitle(for: .regenerate, in: apiKeyState) == "配置后重试",
           "result menu validation uses the adapted retry title")
    expect(ResultCommandFactory.menuToolTip(for: .regenerate, in: apiKeyState) == "先修复 AI 设置,再重新发送请求",
           "result menu tooltip explains configuration retry")

    let contextState = ResultCommandState(hasResult: false,
                                          hasDiagnostics: true,
                                          canWriteBack: false,
                                          isStreaming: false,
                                          hasSourceText: true,
                                          recoveryCode: "context-limit")
    let contextRetry = ResultCommandFactory.descriptors(state: contextState)
        .first { $0.action == .regenerate }
    let contextCommands = ResultCommandFactory.descriptors(state: contextState).map(\.action)
    expect(contextCommands.prefix(2) == [.regenerate, .copyBriefDiagnostics],
           "payload adjustment recovery puts adjusted retry before diagnostics and settings")
    expect(contextCommands.last == .openAISettings,
           "payload adjustment recovery keeps settings available after retry guidance")
    expect(contextRetry?.title == "调整后重试",
           "context failures adapt regenerate to an adjust-first retry command")
    expect(contextRetry?.keywords.contains("缩短") == true,
           "context retry command is searchable by payload adjustment terms")
    expect(ResultCommandFactory.menuTitle(for: .regenerate, in: contextState) == "调整后重试",
           "context retry menu title keeps the adjusted retry action prominent")
    expect(ResultCommandFactory.menuToolTip(for: .regenerate, in: contextState)?.contains("缩短内容") == true,
           "context retry menu tooltip explains the adjustment path")

    let networkState = ResultCommandState(hasResult: false,
                                          hasDiagnostics: true,
                                          canWriteBack: false,
                                          isStreaming: false,
                                          hasSourceText: true,
                                          recoveryCode: "network")
    let networkRetry = ResultCommandFactory.descriptors(state: networkState)
        .first { $0.action == .regenerate }
    let networkCommands = ResultCommandFactory.descriptors(state: networkState).map(\.action)
    expect(networkCommands.prefix(2) == [.regenerate, .copyBriefDiagnostics],
           "transient recovery puts retry before diagnostics and settings in the command palette")
    expect(networkCommands.last == .openAISettings,
           "transient recovery keeps settings available after retry guidance")
    expect(networkRetry?.title == "重试请求",
           "transient failures keep a direct retry command")
}

func testResultCommandFactoryIncludesResultWriteBackAndRegenerateCommands() {
    let state = ResultCommandState(hasResult: true,
                                   hasDiagnostics: true,
                                   canWriteBack: true,
                                   isStreaming: false,
                                   hasSourceText: true)
    let descriptors = ResultCommandFactory.descriptors(state: state)

    expect(descriptors.map(\.id) == [
        "result-copy",
        "result-copy-markdown",
        "result-export",
        "result-copy-brief-diagnostics",
        "result-copy-diagnostics",
        "result-open-ai-settings",
        "result-replace",
        "result-append",
        "result-regenerate"
    ], "result commands appear in stable command palette order")
    expect(descriptors.map(\.action) == [
        .copyOutput,
        .copyMarkdown,
        .exportConversation,
        .copyBriefDiagnostics,
        .copyDiagnostics,
        .openAISettings,
        .replaceOriginal,
        .appendToDocument,
        .regenerate
    ], "result commands carry the expected actions")
    expect(descriptors[3].title == ResultDiagnosticsCommand.briefTitle,
           "brief diagnostics command reuses the shared diagnostics label")
    expect(descriptors[4].title == ResultDiagnosticsCommand.title,
           "full diagnostics command reuses the shared diagnostics label")
    expect(descriptors[5].title == ResultRecoveryCommand.openAISettingsTitle,
           "AI settings recovery command reuses the shared recovery label")
    expect(descriptors[5].subtitle == ResultRecoveryCommand.openAISettingsSubtitle,
           "AI settings recovery command explains provider troubleshooting")
    expect(descriptors[5].keywords.contains("api key") &&
           descriptors[5].keywords.contains("修复"),
           "AI settings recovery command is searchable by request failure terms")
    expect(descriptors[6].subtitle == "先展示差异预览",
           "replace command explains the diff preview")
    expect(descriptors[8].keywords.contains("retry"),
           "regenerate command is searchable by retry")
    expect(ResultCommandFactory.isEnabled(.copyOutput, in: state), "copy output is enabled with a result")
    expect(ResultCommandFactory.isEnabled(.copyMarkdown, in: state), "copy markdown is enabled with a result")
    expect(ResultCommandFactory.isEnabled(.exportConversation, in: state), "export is enabled with a result")
    expect(ResultCommandFactory.isEnabled(.copyBriefDiagnostics, in: state), "brief diagnostics is enabled when diagnostics exist")
    expect(ResultCommandFactory.isEnabled(.copyDiagnostics, in: state), "diagnostics is enabled when diagnostics exist")
    expect(ResultCommandFactory.isEnabled(.openAISettings, in: state), "AI settings recovery is enabled when diagnostics exist")
    expect(ResultCommandFactory.isEnabled(.replaceOriginal, in: state), "replace is enabled when writeback is available")
    expect(ResultCommandFactory.isEnabled(.appendToDocument, in: state), "append is enabled when writeback is available")
    expect(ResultCommandFactory.isEnabled(.regenerate, in: state), "regenerate is enabled after a non-streaming source request")
    expect(!ResultCommandFactory.isEnabled(.stop, in: state), "stop is disabled when not streaming")
}

func testResultCommandFactoryUsesStopWhileStreaming() {
    let state = ResultCommandState(hasResult: true,
                                   hasDiagnostics: false,
                                   canWriteBack: false,
                                   isStreaming: true,
                                   hasSourceText: true)
    let descriptors = ResultCommandFactory.descriptors(state: state)

    expect(descriptors.map(\.id) == [
        "result-copy",
        "result-copy-markdown",
        "result-export",
        "result-stop"
    ], "streaming result commands include stop instead of writeback or regenerate")
    expect(descriptors.last?.action == .stop, "streaming command stops the result request")
    expect(!descriptors.contains(where: { $0.action == .regenerate }),
           "streaming result cannot regenerate until the request finishes")
    expect(!descriptors.contains(where: { $0.action == .replaceOriginal || $0.action == .appendToDocument }),
           "streaming result does not expose writeback commands")
    expect(ResultCommandFactory.isEnabled(.stop, in: state), "stop is enabled while streaming")
    expect(!ResultCommandFactory.isEnabled(.regenerate, in: state), "regenerate is disabled while streaming")
    expect(!ResultCommandFactory.isEnabled(.replaceOriginal, in: state), "replace is disabled while streaming")
    expect(!ResultCommandFactory.isEnabled(.appendToDocument, in: state), "append is disabled while streaming")
}

func testResultCommandFactoryOmitsDiagnosticsWhenUnavailable() {
    let state = ResultCommandState(hasResult: true,
                                   hasDiagnostics: false,
                                   canWriteBack: true,
                                   isStreaming: false,
                                   hasSourceText: false)
    let descriptors = ResultCommandFactory.descriptors(state: state)

    expect(!descriptors.contains(where: { $0.action == .copyBriefDiagnostics || $0.action == .copyDiagnostics }),
           "result command hides diagnostics when no diagnostics text exists")
    expect(!descriptors.contains(where: { $0.action == .openAISettings }),
           "result command hides AI settings recovery when no diagnostics text exists")
    expect(!descriptors.contains(where: { $0.action == .regenerate }),
           "result command hides regenerate when no source text exists")
    expect(descriptors.contains(where: { $0.action == .replaceOriginal }),
           "writeback command still appears when writeback is available")
    expect(!ResultCommandFactory.isEnabled(.copyBriefDiagnostics, in: state),
           "brief diagnostics command is disabled without diagnostics text")
    expect(!ResultCommandFactory.isEnabled(.copyDiagnostics, in: state),
           "diagnostics command is disabled without diagnostics text")
    expect(!ResultCommandFactory.isEnabled(.openAISettings, in: state),
           "AI settings recovery command is disabled without diagnostics text")
    expect(!ResultCommandFactory.isEnabled(.regenerate, in: state),
           "regenerate command is disabled without source text")
}

func testResultCommandFactoryShowsRecoverySettingsWithoutDiagnostics() {
    let state = ResultCommandState(hasResult: false,
                                   hasDiagnostics: false,
                                   canWriteBack: false,
                                   isStreaming: false,
                                   hasSourceText: true,
                                   recoveryCode: "api-key")
    let descriptors = ResultCommandFactory.descriptors(state: state)

    expect(!descriptors.contains(where: { $0.action == .copyBriefDiagnostics || $0.action == .copyDiagnostics }),
           "recovery-only command state still hides diagnostics commands")
    expect(descriptors.map(\.action) == [.openAISettings, .regenerate],
           "recovery-only command state keeps settings fix before retry for configuration failures")
    expect(descriptors.first?.title == "填写 API Key",
           "recovery-only command state exposes the concrete settings fix")
    expect(descriptors.last?.title == "配置后重试",
           "recovery-only command state keeps retry available after the fix")
    expect(ResultCommandFactory.isEnabled(.openAISettings, in: state),
           "AI settings recovery is enabled when a recovery code exists without diagnostics")
    expect(!ResultCommandFactory.isEnabled(.copyBriefDiagnostics, in: state),
           "brief diagnostics remain disabled without diagnostics text")
    expect(!ResultCommandFactory.isEnabled(.copyDiagnostics, in: state),
           "full diagnostics remain disabled without diagnostics text")
}

func testHistoryEntryMarkdownExport() {
    let entry = HistoryEntry(date: Date(timeIntervalSince1970: 0),
                             actionName: "总结",
                             source: "原始内容",
                             output: "总结结果",
                             provider: "OpenAI",
                             model: "gpt-4o-mini",
                             isFavorite: true,
                             tags: ["工作", "摘要"])
    let markdown = entry.markdownExport
    expect(markdown.contains("# 总结"), "exports action as title")
    expect(markdown.contains("- 模型: OpenAI / gpt-4o-mini"), "exports model metadata")
    expect(markdown.contains("- 收藏: 是"), "exports favorite state")
    expect(markdown.contains("- 标签: 工作, 摘要"), "exports tags")
    expect(markdown.contains("## 原文\n\n原始内容"), "exports source")
    expect(markdown.contains("## 结果\n\n总结结果"), "exports output")

    let blank = HistoryEntry(actionName: "空记录",
                             source: " \n ",
                             output: "",
                             provider: "OpenAI",
                             model: "gpt")
    expect(blank.sourceExportText == "无原文", "blank history source exports explicit placeholder")
    expect(blank.outputExportText == "无结果", "blank history output exports explicit placeholder")
    expect(blank.copyableOutputText == nil, "blank history has no copyable output")
    expect(blank.reopenSourceText == nil, "blank history has no source for reopening")
    expect(!blank.canReopen, "blank history cannot reopen as a request")
    expect(blank.reopenHelpText == "该记录未保存原文", "blank history explains why reopening is unavailable")
    expect(!blank.isMetadataOnlyRecord, "blank history without metadata tag is not treated as metadata-only")
    expect(blank.emptyContentPlaceholder == "无原文或结果", "blank non-metadata history uses generic placeholder")
    expect(blank.markdownExport.contains("## 原文\n\n无原文"), "blank source markdown is explicit")
    expect(blank.markdownExport.contains("## 结果\n\n无结果"), "blank output markdown is explicit")

    let metadataOnly = HistoryEntry(actionName: "隐私审计",
                                    source: "",
                                    output: "",
                                    provider: "OpenAI",
                                    model: "gpt",
                                    tags: [PrivacyHistoryTag.metadataOnly])
    expect(metadataOnly.copyableOutputText == nil, "metadata-only history has no copyable output")
    expect(metadataOnly.reopenSourceText == nil, "metadata-only history has no source for reopening")
    expect(!metadataOnly.canReopen, "metadata-only history cannot reopen as a request")
    expect(metadataOnly.reopenHelpText == "该记录未保存原文", "metadata-only history explains why reopening is unavailable")
    expect(metadataOnly.isMetadataOnlyRecord, "metadata-only history is recognized by tag and empty content")
    expect(metadataOnly.emptyContentPlaceholder == "仅保存元信息,未保存原文与结果",
           "metadata-only history explains why content is absent")
    expect(metadataOnly.sourceExportText == "仅保存元信息,未保存原文",
           "metadata-only history export explains missing source")
    expect(metadataOnly.outputExportText == "仅保存元信息,未保存结果",
           "metadata-only history export explains missing output")
    expect(metadataOnly.markdownExport.contains("## 原文\n\n仅保存元信息,未保存原文"),
           "metadata-only markdown explains missing source")
    expect(metadataOnly.markdownExport.contains("## 结果\n\n仅保存元信息,未保存结果"),
           "metadata-only markdown explains missing output")

    let tagged = HistoryEntry(actionName: "总结",
                              source: "原文",
                              output: "结果",
                              provider: "OpenAI",
                              model: "gpt",
                              tags: [" 工作 ", "", "摘要", "工作"])
    expect(tagged.displayTags == ["工作", "摘要"], "history display tags trim, drop blanks and dedupe")
    expect(tagged.reopenSourceText == "原文", "history with source can reopen from display source")
    expect(tagged.canReopen, "history with source can reopen as a request")
    expect(tagged.reopenHelpText == "重新发起", "history with source exposes reopen help text")
    expect(tagged.markdownExport.contains("- 标签: 工作, 摘要"), "history markdown exports display tags")

    let dirtyMetadata = HistoryEntry(actionName: "  总结  ",
                                     source: "原文",
                                     output: "结果",
                                     provider: "  OpenAI  ",
                                     model: "  gpt-4o-mini  ")
    expect(dirtyMetadata.displayActionName == "总结", "history display action trims surrounding whitespace")
    expect(dirtyMetadata.modelDisplayText == "OpenAI / gpt-4o-mini", "history model display trims provider and model")
    expect(dirtyMetadata.markdownExport.contains("# 总结"), "history markdown exports display action")
    expect(dirtyMetadata.markdownExport.contains("- 模型: OpenAI / gpt-4o-mini"),
           "history markdown exports display model metadata")

    let missingModel = HistoryEntry(actionName: "总结",
                                    source: "原文",
                                    output: "结果",
                                    provider: " OpenAI ",
                                    model: " ")
    expect(missingModel.displayModelFilterName == "未知模型", "history model facet uses explicit unknown fallback")
    expect(missingModel.modelDisplayText == "OpenAI / 未知模型", "history model display keeps provider with unknown model")
    expect(missingModel.commandPaletteKeywords.contains("未知模型"), "history command keywords include unknown model fallback")

    let unsafeMetadata = HistoryEntry(actionName: "总结 sk-live-secret-value-1234567890",
                                      source: "正文可保留 sk-live-secret-value-1234567890",
                                      output: "结果",
                                      provider: "OpenAI\nTeam",
                                      model: "gpt|4o `mini` sk-model-secret-value-1234567890",
                                      tags: ["发布 sk-tag-secret-value-1234567890"])
    let unsafeMarkdown = unsafeMetadata.markdownExport
    expect(unsafeMarkdown.contains("# 总结 [REDACTED_KEY]"),
           "history markdown redacts key-like action metadata")
    expect(unsafeMarkdown.contains("- 模型: OpenAI Team / gpt/4o 'mini' [REDACTED_KEY]"),
           "history markdown redacts key-like model metadata and keeps it single-line")
    expect(unsafeMarkdown.contains("- 标签: 发布 [REDACTED_KEY]"),
           "history markdown redacts key-like tag metadata")
    expect(!unsafeMarkdown.contains("sk-model-secret-value-1234567890"),
           "history markdown does not leak key-like model metadata")
    expect(!unsafeMarkdown.contains("sk-tag-secret-value-1234567890"),
           "history markdown does not leak key-like tag metadata")
    expect(unsafeMarkdown.contains("正文可保留 sk-live-secret-value-1234567890"),
           "history markdown preserves user source body content")
}

func testHistoryEntryCompactTitlesForMenus() {
    let longSource = "第一行内容\n\n第二行内容    第三行内容以及一段很长很长的说明文字"
    let entry = HistoryEntry(actionName: "总结",
                             source: longSource,
                             output: "输出内容",
                             provider: "OpenAI",
                             model: "gpt-4o-mini")

    expect(entry.preview == "第一行内容 第二行内容 第三行内容以及一段很长很长的说明文字",
           "history preview collapses whitespace when it fits")
    expect(!entry.menuTitle.contains("\n"), "history menu title is single-line")
    expect(entry.menuTitle.hasPrefix("[总结] "), "history menu title keeps action context")
    expect(entry.menuTitle.count <= 30, "history menu title stays short for menu bar")

    let fallback = HistoryEntry(actionName: "",
                                source: " \n ",
                                output: "用输出作为标题",
                                provider: "OpenAI",
                                model: "gpt-4o-mini")
    expect(fallback.sourceDisplayText == nil, "blank history source has no display text")
    expect(fallback.outputDisplayText == "用输出作为标题", "non-empty history output is displayable")
    expect(fallback.preview == "用输出作为标题", "history preview falls back to output when source is empty")
    expect(fallback.menuTitle == "用输出作为标题", "history menu title falls back to output when source is empty")

    let actionOnly = HistoryEntry(actionName: "空结果动作",
                                  source: "",
                                  output: "",
                                  provider: "OpenAI",
                                  model: "gpt")
    expect(actionOnly.sourceDisplayText == nil, "empty source has no display text")
    expect(actionOnly.outputDisplayText == nil, "empty output has no display text")
    expect(actionOnly.preview == "空结果动作", "history preview falls back to action name when source and output are empty")
    expect(actionOnly.menuTitle == "空结果动作",
           "history menu title avoids duplicating the action when no source or output exists")

    let tiny = HistoryEntry(actionName: "动作",
                            source: "abcdef",
                            output: "",
                            provider: "OpenAI",
                            model: "gpt")
    expect(tiny.menuTitle(maxLength: 1) == "…", "history menu title handles tiny limits")
}

func testHistoryEntryCommandPaletteKeywordsCoverMetadata() {
    let entry = HistoryEntry(date: Date(timeIntervalSince1970: 0),
                             actionName: "总结",
                             source: "release notes",
                             output: "权限诊断",
                             provider: "OpenAI",
                             model: "gpt-4o-mini",
                             isFavorite: true,
                             tags: ["发布", "  ", "诊断", "发布", "多余"])
    let keywords = entry.commandPaletteKeywords
    expect(keywords.contains("总结"), "history command keywords include action")
    expect(keywords.contains("release notes"), "history command keywords include source")
    expect(keywords.contains("权限诊断"), "history command keywords include output")
    expect(keywords.contains("OpenAI"), "history command keywords include provider")
    expect(keywords.contains("gpt-4o-mini"), "history command keywords include model")
    expect(keywords.contains("发布"), "history command keywords include tags")
    expect(!keywords.contains("  "), "history command keywords omit blank tags")
    expect(keywords.components(separatedBy: "发布").count == 2, "history command keywords dedupe repeated tags")

    let subtitle = entry.commandPaletteSubtitle
    expect(subtitle.contains("历史记录"), "history command subtitle identifies history entries")
    expect(subtitle.contains("总结"), "history command subtitle includes action")
    expect(subtitle.contains("OpenAI / gpt-4o-mini"), "history command subtitle includes provider and model")
    expect(subtitle.contains("收藏"), "history command subtitle includes favorite state")
    expect(subtitle.contains("#发布 #诊断"), "history command subtitle includes compact tag summary")
    expect(!subtitle.contains("多余"), "history command subtitle limits tag summary")
    expect(subtitle.count <= 72, "history command subtitle stays compact")

    let longMetadata = HistoryEntry(actionName: "非常非常长的动作名称用于测试命令面板副标题是否会过长",
                                    source: "source",
                                    output: "output",
                                    provider: "VeryLongProviderNameForCommandPalette",
                                    model: "very-long-model-name-for-command-palette-display",
                                    tags: ["很长的标签一", "很长的标签二"])
    expect(longMetadata.commandPaletteSubtitle.count <= 72,
           "long history command subtitle is capped by default")
    expect(longMetadata.commandPaletteSubtitle(maxLength: 1) == "…",
           "history command subtitle handles tiny limits")

    let dirtyMetadata = HistoryEntry(actionName: " 总结 ",
                                     source: "source",
                                     output: "output",
                                     provider: " OpenAI ",
                                     model: " gpt ",
                                     tags: [" 发布 "])
    expect(dirtyMetadata.commandPaletteSubtitle.contains("总结 - OpenAI / gpt"),
           "history command subtitle uses display metadata")
    expect(!dirtyMetadata.commandPaletteSubtitle.contains("  OpenAI  "),
           "history command subtitle avoids raw padded metadata")

    let longSource = "开头可搜索 " + String(repeating: "长原文", count: 500) + " 尾部不应进入命令面板关键词"
    let longOutput = "输出可搜索 " + String(repeating: "长结果", count: 500)
    let longContent = HistoryEntry(actionName: "总结",
                                   source: longSource,
                                   output: longOutput,
                                   provider: "OpenAI",
                                   model: "gpt")
    let longKeywords = longContent.commandPaletteKeywords
    expect(longKeywords.contains("开头可搜索"), "history command keywords keep searchable source prefix")
    expect(longKeywords.contains("输出可搜索"), "history command keywords keep searchable output prefix")
    expect(!longKeywords.contains("尾部不应进入命令面板关键词"),
           "history command keywords omit far-tail long source content")
    expect(longKeywords.count < 1_400, "history command keywords cap long source and output snippets")

    let sensitive = HistoryEntry(actionName: "总结\napi_key=actionsecret123456",
                                 source: "Authorization: Bearer sourceToken123456 keep-searchable",
                                 output: "password=outputsecret123456 sk-proj-history-secret-1234567890",
                                 provider: "Provider|`P`",
                                 model: "model\nsk-proj-model-secret-1234567890",
                                 tags: ["tag|`x`"])
    let sensitiveKeywords = sensitive.commandPaletteKeywords
    expect(sensitiveKeywords.contains("keep-searchable"),
           "history command keywords keep non-sensitive searchable content")
    expect(!sensitiveKeywords.contains("actionsecret123456") &&
           !sensitiveKeywords.contains("sourceToken123456") &&
           !sensitiveKeywords.contains("outputsecret123456") &&
           !sensitiveKeywords.contains("sk-proj-history-secret-1234567890") &&
           !sensitiveKeywords.contains("sk-proj-model-secret-1234567890"),
           "history command keywords redact key-like metadata and content fragments")
    expect(!sensitiveKeywords.contains("\n") &&
           !sensitiveKeywords.contains("|") &&
           !sensitiveKeywords.contains("`"),
           "history command keywords are single-line and markdown-safe")
}

func testHistoryFilterCriteriaMatchesMultipleTermsAndFacets() {
    let favorite = HistoryEntry(date: Date(timeIntervalSince1970: 0),
                                actionName: " 总结 ",
                                source: "SnapAI release notes",
                                output: "权限和更新诊断",
                                provider: "OpenAI",
                                model: " gpt-4o-mini ",
                                isFavorite: true,
                                tags: [" 发布 ", "诊断", "发布", ""])
    let other = HistoryEntry(date: Date(timeIntervalSince1970: 1),
                             actionName: "翻译",
                             source: "hello",
                             output: "你好",
                             provider: "Anthropic",
                             model: "claude-sonnet",
                             tags: ["临时"])
    let privacy = HistoryEntry(date: Date(timeIntervalSince1970: 2),
                               actionName: "隐私/审计",
                               source: "联系 [邮箱]",
                               output: "结果",
                               provider: "OpenAI",
                               model: "privacy-model",
                               tags: ["本地脱敏", "隐私预览"])
    let entries = [favorite, other, privacy]

    let queryCriteria = HistoryFilterCriteria(query: "release 诊断")
    expect(queryCriteria.apply(to: entries).map(\.id) == [favorite.id], "matches multi-term history query")
    expect(HistoryFilterCriteria.normalizedQueryTerms("release/诊断+gpt-4o") == ["release", "诊断", "gpt", "4o"],
           "normalizes history query separators")
    expect(HistoryFilterCriteria(query: "release-notes/诊断").apply(to: entries).map(\.id) == [favorite.id],
           "matches history queries separated by punctuation")
    expect(HistoryFilterCriteria(query: "gpt-4o").apply(to: entries).map(\.id) == [favorite.id],
           "matches hyphenated model query terms")
    expect(HistoryFilterCriteria(query: "gpt4omini").apply(to: entries).map(\.id) == [favorite.id],
           "matches compact model query terms")
    expect(HistoryFilterCriteria(query: "发布").apply(to: entries).map(\.id) == [favorite.id],
           "matches normalized display tags in free-text query")
    expect(HistoryFilterCriteria(query: "隐私审计 本地脱敏").apply(to: entries).map(\.id) == [privacy.id],
           "matches compact action and privacy tag terms")
    expect(HistoryFilterCriteria.facetValues([" 总结 ", "", "翻译", "总结", " \n "]) == ["翻译", "总结"],
           "history facet values trim blanks, remove empties, dedupe and sort")
    let facetCounts = HistoryFilterCriteria.rankedFacetCounts([" 项目A ", "项目B", "项目A", "", "项目B", "项目B"])
    expect(facetCounts.map(\.value) == ["项目B", "项目A"],
           "history facet counts sort by count then name")
    expect(facetCounts.map(\.count) == [3, 2],
           "history facet counts trim and filter values")

    let facetCriteria = HistoryFilterCriteria(actionFilter: "总结",
                                              modelFilter: "gpt-4o-mini",
                                              tagFilter: "发布",
                                              favoriteOnly: true)
    expect(facetCriteria.apply(to: entries).map(\.id) == [favorite.id],
           "matches normalized action/model/tag/favorite facets")
    let paddedFacetCriteria = HistoryFilterCriteria(actionFilter: " 总结 ",
                                                    modelFilter: " gpt-4o-mini ",
                                                    tagFilter: " 发布 ")
    expect(paddedFacetCriteria.apply(to: entries).map(\.id) == [favorite.id],
           "normalizes selected history facet filters before matching")

    let missCriteria = HistoryFilterCriteria(query: "release",
                                             actionFilter: "翻译")
    expect(missCriteria.apply(to: entries).isEmpty, "rejects entries outside selected action facet")
    expect(HistoryFilterCriteria(actionFilter: "隐私 审计").apply(to: entries).map(\.id) == [privacy.id],
           "history action facet ignores common separators")
    expect(HistoryFilterCriteria(modelFilter: "gpt4omini").apply(to: entries).map(\.id) == [favorite.id],
           "history model facet ignores common separators")
    expect(HistoryFilterCriteria(tagFilter: "本地-脱敏").apply(to: entries).map(\.id) == [privacy.id],
           "history tag facet ignores common separators for privacy tags")
    expect(facetCriteria.summaryText.contains("仅收藏"), "summarizes favorite filter")
    expect(facetCriteria.summaryText.contains("标签: 发布"), "summarizes tag filter")
}

func testHistoryFilterCriteriaMatchesDisplayFallbacks() {
    let unnamed = HistoryEntry(actionName: " \n ",
                               source: "空动作历史",
                               output: "结果",
                               provider: " OpenAI ",
                               model: " gpt   4o ")
    let missingModel = HistoryEntry(actionName: "总结",
                                    source: "缺少模型",
                                    output: "结果",
                                    provider: " OpenAI ",
                                    model: " ")
    let normal = HistoryEntry(actionName: "总结",
                              source: "普通历史",
                              output: "结果",
                              provider: "OpenAI",
                              model: "gpt")
    let entries = [unnamed, missingModel, normal]

    expect(HistoryFilterCriteria(actionFilter: "未命名动作").apply(to: entries).map(\.id) == [unnamed.id],
           "history action facet matches display fallback names")
    expect(HistoryFilterCriteria(modelFilter: "gpt 4o").apply(to: entries).map(\.id) == [unnamed.id],
           "history model facet matches collapsed display model names")
    expect(HistoryFilterCriteria(modelFilter: "未知模型").apply(to: entries).map(\.id) == [missingModel.id],
           "history model facet matches unknown model fallback")
    expect(HistoryFilterCriteria(modelFilter: "OpenAI").apply(to: entries).isEmpty,
           "history model facet does not treat provider as model fallback")
    expect(HistoryFilterCriteria(query: "未命名动作 gpt 4o").apply(to: entries).map(\.id) == [unnamed.id],
           "history free-text query searches display fallback metadata")
    expect(HistoryFilterCriteria(query: "未知模型").apply(to: entries).map(\.id) == [missingModel.id],
           "history free-text query searches unknown model fallback")
}

func testHistoryCollectionExportMarkdown() {
    let entry = HistoryEntry(date: Date(timeIntervalSince1970: 0),
                             actionName: "总结",
                             source: "原始内容",
                             output: "总结结果",
                             provider: "OpenAI",
                             model: "gpt-4o-mini",
                             tags: ["工作"])
    let criteria = HistoryFilterCriteria(query: "原始",
                                         actionFilter: "总结")
    let export = HistoryCollectionExport(entries: [entry],
                                         criteria: criteria,
                                         date: Date(timeIntervalSince1970: 0))
    let markdown = export.markdown
    expect(markdown.contains("# SnapAI 历史记录"), "exports collection title")
    expect(markdown.contains("- 筛选条件: 搜索: 原始 / 动作: 总结"), "exports filter summary")
    expect(markdown.contains("- 记录数量: 1"), "exports entry count")
    expect(markdown.contains("## 1. 总结 - 01-01 08:00") || markdown.contains("## 1. 总结 - 12-31"),
           "exports numbered entry heading with local date")
    expect(markdown.contains("## 原文\n\n原始内容"), "includes entry source")
    expect(markdown.contains("## 结果\n\n总结结果"), "includes entry output")

    let unsafeEntry = HistoryEntry(date: Date(timeIntervalSince1970: 0),
                                   actionName: "总结\n# 注入",
                                   source: "原文\n保留换行",
                                   output: "结果",
                                   provider: "OpenAI\n团队",
                                   model: "gpt|4o\nmini",
                                   tags: ["工作\n项目", "发布`标签", String(repeating: "长", count: 80)])
    let unsafeExport = HistoryCollectionExport(title: "SnapAI\n历史|记录",
                                               entries: [unsafeEntry],
                                               criteria: HistoryFilterCriteria(query: "客户\nA",
                                                                               tagFilter: "工作|项目"),
                                               date: Date(timeIntervalSince1970: 0))
    let unsafeMarkdown = unsafeExport.markdown
    expect(unsafeMarkdown.contains("# SnapAI 历史/记录"), "history export keeps collection title single-line")
    expect(unsafeMarkdown.contains("- 筛选条件: 搜索: 客户 A / 标签: 工作/项目"),
           "history export keeps criteria summary single-line")
    expect(unsafeMarkdown.contains("## 1. 总结 # 注入 -"), "history export keeps entry heading single-line")
    expect(unsafeMarkdown.contains("- 模型: OpenAI 团队 / gpt/4o mini"),
           "history export keeps model metadata single-line and table-safe")
    expect(unsafeMarkdown.contains("- 标签: 工作 项目, 发布'标签"),
           "history export keeps tag metadata single-line and code-safe")
    expect(!unsafeMarkdown.contains("SnapAI\n历史"), "history export does not allow newline injection in title")
    expect(!unsafeMarkdown.contains("总结\n# 注入"), "history export does not allow newline injection in action metadata")
    expect(!unsafeMarkdown.contains("工作\n项目"), "history export does not allow newline injection in tags")
    expect(unsafeMarkdown.contains("## 原文\n\n原文\n保留换行"), "history export preserves source body newlines")

    let secretCriteriaExport = HistoryCollectionExport(
        title: "SnapAI sk-title-secret-value-1234567890",
        entries: [unsafeEntry],
        criteria: HistoryFilterCriteria(query: "sk-query-secret-value-1234567890",
                                        modelFilter: "gpt sk-filter-secret-value-1234567890"),
        date: Date(timeIntervalSince1970: 0)
    )
    let secretCriteriaMarkdown = secretCriteriaExport.markdown
    expect(secretCriteriaMarkdown.contains("# SnapAI [REDACTED_KEY]"),
           "history collection export redacts key-like title metadata")
    expect(secretCriteriaMarkdown.contains("- 筛选条件: 搜索: [REDACTED_KEY] / 模型: gpt [REDACTED_KEY]"),
           "history collection export redacts key-like filter metadata")
    expect(!secretCriteriaMarkdown.contains("sk-title-secret-value-1234567890"),
           "history collection export does not leak title key-like metadata")
    expect(!secretCriteriaMarkdown.contains("sk-query-secret-value-1234567890"),
           "history collection export does not leak query key-like metadata")

    let empty = HistoryCollectionExport(entries: [],
                                        criteria: HistoryFilterCriteria(),
                                        date: Date(timeIntervalSince1970: 0))
    expect(empty.markdown.contains("无匹配记录。"), "explains empty exports")
}

func testHistoryContextProfileBuilderCreatesSafeContextDraft() {
    let date = Date(timeIntervalSince1970: 0)
    let useful = HistoryEntry(date: date,
                              actionName: "润色",
                              source: "SnapAI 是菜单栏 AI 工具。",
                              output: "SnapAI 是一款菜单栏 AI 工具。",
                              provider: "OpenAI",
                              model: "gpt-4o-mini",
                              tags: ["产品", "写作"])
    let outputOnly = HistoryEntry(date: date,
                                  actionName: "总结",
                                  source: "",
                                  output: "用户希望提升替换原文的稳定性。",
                                  provider: "DeepSeek",
                                  model: "deepseek-chat")
    let metadataOnly = HistoryEntry(date: date,
                                    actionName: "隐私审计",
                                    source: "",
                                    output: "",
                                    provider: "OpenAI",
                                    model: "gpt",
                                    tags: [PrivacyHistoryTag.metadataOnly])
    let blank = HistoryEntry(date: date,
                             actionName: "空记录",
                             source: " \n ",
                             output: "",
                             provider: "OpenAI",
                             model: "gpt")
    let criteria = HistoryFilterCriteria(query: "SnapAI",
                                         actionFilter: "润色",
                                         tagFilter: "产品")

    guard let draft = HistoryContextProfileBuilder.draft(entries: [useful, metadataOnly, blank, outputOnly],
                                                         criteria: criteria,
                                                         date: date,
                                                         maxEntries: 5,
                                                         maxFieldCharacters: 19) else {
        expect(false, "creates context draft when at least one history entry has content")
        return
    }

    expect(draft.name.hasPrefix("历史上下文 - 搜索: SnapAI"), "context draft name summarizes active filters")
    expect(draft.includedCount == 2, "context draft includes usable entries")
    expect(draft.skippedCount == 2, "context draft skips metadata-only and blank entries")
    expect(draft.profile.name == draft.name, "context draft creates an enabled context profile")
    expect(draft.profile.isEnabled, "generated context profile is enabled")

    let content = draft.content
    expect(content.contains("# SnapAI 历史上下文"), "context draft has a clear title")
    expect(content.contains("- 来源筛选: 搜索: SnapAI / 动作: 润色 / 标签: 产品"), "context draft records source filters")
    expect(content.contains("- 写入记录: 2"), "context draft records included count")
    expect(content.contains("- 跳过记录: 2"), "context draft records skipped count")
    expect(content.contains("## 1. 润色"), "context draft numbers included entries")
    expect(content.contains("- 模型: OpenAI / gpt-4o-mini"), "context draft includes model metadata")
    expect(content.contains("- 标签: #产品 #写作"), "context draft includes display tags")
    expect(content.contains("原文:\nSnapAI 是菜单栏 AI 工具。"), "context draft includes source text")
    expect(content.contains("[已截断]"), "context draft truncates long fields")
    expect(content.contains("用户希望提升替换原文"), "context draft can include output-only entries")
    expect(!content.contains("仅保存元信息"), "context draft does not copy metadata-only placeholders")
    expect(!content.contains("隐私审计"), "context draft omits metadata-only entries")
    expect(!content.contains("空记录"), "context draft omits blank entries")

    let allHistoryMorning = HistoryContextProfileBuilder.draft(entries: [useful],
                                                               criteria: HistoryFilterCriteria(),
                                                               date: Date(timeIntervalSince1970: 0))
    let allHistoryLater = HistoryContextProfileBuilder.draft(entries: [useful],
                                                             criteria: HistoryFilterCriteria(),
                                                             date: Date(timeIntervalSince1970: 3_600))
    expect(allHistoryMorning?.name == "历史上下文 - 全部历史",
           "all-history context draft uses a stable name")
    expect(allHistoryMorning?.name == allHistoryLater?.name,
           "all-history context draft name does not depend on generation time")

    let limitedDraft = HistoryContextProfileBuilder.draft(entries: [useful, outputOnly, metadataOnly],
                                                          criteria: HistoryFilterCriteria(),
                                                          date: date,
                                                          maxEntries: 1,
                                                          maxFieldCharacters: 1_000)
    expect(limitedDraft?.includedCount == 1, "context draft maxEntries limits included records")
    expect(limitedDraft?.skippedCount == 2, "context draft maxEntries contributes to skipped count")
    expect(limitedDraft?.content.contains("SnapAI 是菜单栏 AI 工具。") == true,
           "context draft maxEntries keeps the first usable record")
    expect(limitedDraft?.content.contains("用户希望提升替换原文") == false,
           "context draft maxEntries omits later usable records")

    expect(HistoryContextProfileBuilder.draft(entries: [metadataOnly, blank],
                                              criteria: HistoryFilterCriteria(),
                                              date: date) == nil,
           "context draft is unavailable when no history content can be written")
}

func testHistoryContextProfileBuilderSanitizesMetadata() {
    let date = Date(timeIntervalSince1970: 0)
    let entry = HistoryEntry(date: date,
                             actionName: "总结\n# 注入|`A`",
                             source: "原文第一行\n原文第二行",
                             output: "结果第一行\n结果第二行",
                             provider: "OpenAI\nProvider|`B`",
                             model: "gpt|4o\nmini sk-live-secret-value-1234567890",
                             tags: ["项目\n# 注入|`Tag`"])
    let criteria = HistoryFilterCriteria(query: "SnapAI\n# 注入|`Q`",
                                         actionFilter: "总结\n# 注入|`A`",
                                         tagFilter: "项目\n# 注入|`Tag`")

    guard let draft = HistoryContextProfileBuilder.draft(entries: [entry],
                                                         criteria: criteria,
                                                         date: date,
                                                         maxEntries: 5,
                                                         maxFieldCharacters: 1_000) else {
        expect(false, "creates context draft for unsafe metadata fixture")
        return
    }

    expect(draft.name.hasPrefix("历史上下文 - 搜索: SnapAI") && draft.name.hasSuffix("..."),
           "context draft name keeps unsafe criteria metadata readable and bounded")
    expect(!draft.name.contains("\n"), "context draft name does not allow newline injection")
    expect(!draft.name.contains("|") && !draft.name.contains("`"),
           "context draft name removes markdown table and code fence metadata characters")

    let content = draft.content
    expect(content.contains("- 来源筛选: 搜索: SnapAI # 注入/'Q' / 动作: 总结 # 注入/'A' / 标签: 项目 # 注入/'Tag'"),
           "context draft source filter metadata is single-line and code-safe")
    expect(content.contains("## 1. 总结 # 注入/'A' - 01-01 08:00"),
           "context draft entry heading metadata is single-line and code-safe")
    expect(content.contains("- 模型: OpenAI Provider/'B' / gpt/4o mini [REDACTED_KEY]"),
           "context draft model metadata is sanitized and redacts accidental keys")
    expect(content.contains("- 标签: #项目 # 注入/'Tag'"),
           "context draft tag metadata is single-line and code-safe")
    expect(!content.contains("总结\n# 注入"), "context draft does not allow action metadata newline injection")
    expect(!content.contains("OpenAI\nProvider"), "context draft does not allow model metadata newline injection")
    expect(!content.contains("sk-live-secret-value-1234567890"),
           "context draft does not leak key-like metadata")
    expect(content.contains("原文:\n原文第一行\n原文第二行"),
           "context draft preserves source body newlines")
    expect(content.contains("结果:\n结果第一行\n结果第二行"),
           "context draft preserves output body newlines")
}

func testAppSettingsUpsertsHistoryContextProfileByName() {
    let settings = AppSettings()
    settings.contextProfiles = []
    settings.activeContextProfileID = ""

    let firstDraft = HistoryContextProfileDraft(name: " 历史上下文 - 项目A ",
                                                content: "旧上下文",
                                                includedCount: 1,
                                                skippedCount: 0)
    let first = settings.upsertContextProfile(from: firstDraft)

    expect(!first.didUpdate, "first history context upsert creates a new profile")
    expect(settings.contextProfiles.count == 1, "history context upsert appends when no matching profile exists")
    expect(settings.contextProfiles[0].name == "历史上下文 - 项目A", "history context upsert trims generated names")
    expect(settings.contextProfiles[0].content == "旧上下文", "history context upsert stores draft content")
    expect(settings.contextProfiles[0].isEnabled, "history context upsert creates enabled profiles")
    expect(settings.activeContextProfileID == first.profile.id, "history context upsert activates created profile")
    expect(settings.hasContextProfile(named: "历史上下文 - 项目A"), "history context lookup finds trimmed names")

    let originalID = first.profile.id
    settings.contextProfiles[0].isEnabled = false
    settings.activeContextProfileID = "other"

    let secondDraft = HistoryContextProfileDraft(name: "历史上下文 - 项目A",
                                                 content: "新上下文",
                                                 includedCount: 2,
                                                 skippedCount: 1)
    let second = settings.upsertContextProfile(from: secondDraft)

    expect(second.didUpdate, "second history context upsert updates matching profile")
    expect(settings.contextProfiles.count == 1, "history context upsert avoids duplicate generated profiles")
    expect(settings.contextProfiles[0].id == originalID, "history context upsert preserves existing profile id")
    expect(settings.contextProfiles[0].content == "新上下文", "history context upsert refreshes existing content")
    expect(settings.contextProfiles[0].isEnabled, "history context upsert re-enables existing profile")
    expect(settings.activeContextProfileID == originalID, "history context upsert activates updated profile")
    expect(second.profile.id == originalID, "history context upsert result returns updated profile")

    let generatedSettings = AppSettings()
    generatedSettings.contextProfiles = []
    let entry = HistoryEntry(actionName: "总结",
                             source: "原文",
                             output: "第一次",
                             provider: "OpenAI",
                             model: "gpt")
    let updatedEntry = HistoryEntry(actionName: "总结",
                                    source: "原文",
                                    output: "第二次",
                                    provider: "OpenAI",
                                    model: "gpt")
    guard let generatedFirst = HistoryContextProfileBuilder.draft(entries: [entry],
                                                                  criteria: HistoryFilterCriteria(),
                                                                  date: Date(timeIntervalSince1970: 0)),
          let generatedSecond = HistoryContextProfileBuilder.draft(entries: [updatedEntry],
                                                                   criteria: HistoryFilterCriteria(),
                                                                   date: Date(timeIntervalSince1970: 3_600)) else {
        expect(false, "creates generated all-history context drafts")
        return
    }
    let generatedResult = generatedSettings.upsertContextProfile(from: generatedFirst)
    let generatedUpdate = generatedSettings.upsertContextProfile(from: generatedSecond)
    expect(generatedResult.profile.name == "历史上下文 - 全部历史",
           "generated all-history context upsert uses stable profile name")
    expect(generatedUpdate.didUpdate, "repeated all-history context upsert updates existing profile")
    expect(generatedSettings.contextProfiles.count == 1,
           "repeated all-history context upsert avoids duplicate timestamped profiles")
    expect(generatedSettings.contextProfiles[0].content.contains("第二次"),
           "repeated all-history context upsert refreshes generated content")

    var namedDraft = generatedFirst
    namedDraft.name = "项目A上下文"
    var namedUpdateDraft = generatedSecond
    namedUpdateDraft.name = " 项目A上下文 "
    let namedSettings = AppSettings()
    namedSettings.contextProfiles = []
    let namedCreate = namedSettings.upsertContextProfile(from: namedDraft)
    let namedUpdate = namedSettings.upsertContextProfile(from: namedUpdateDraft)
    expect(namedCreate.profile.name == "项目A上下文", "custom history context names are preserved")
    expect(namedUpdate.didUpdate, "custom named history context upsert updates matching profile")
    expect(namedSettings.contextProfiles.count == 1, "custom named history context avoids duplicate profiles")
    expect(namedSettings.contextProfiles[0].id == namedCreate.profile.id,
           "custom named history context upsert preserves profile identity")
}

func testHistoryContextCommandFactoryBuildsUsableContextCommands() {
    let useful = HistoryEntry(actionName: "总结",
                              source: "项目背景",
                              output: "项目结论",
                              provider: "OpenAI",
                              model: "gpt-4o-mini",
                              isFavorite: true,
                              tags: ["项目A"])
    let outputOnly = HistoryEntry(actionName: "总结",
                                  source: "",
                                  output: "可复用结论",
                                  provider: "OpenAI",
                                  model: "gpt-4o-mini",
                                  tags: ["项目A"])
    let metadataOnly = HistoryEntry(actionName: "隐私审计",
                                    source: "",
                                    output: "",
                                    provider: "OpenAI",
                                    model: "gpt",
                                    isFavorite: true,
                                    tags: [PrivacyHistoryTag.metadataOnly, "项目A"])
    let blank = HistoryEntry(actionName: "空记录",
                             source: " \n ",
                             output: "",
                             provider: "OpenAI",
                             model: "gpt")

    let descriptors = HistoryContextCommandFactory.descriptors(for: [useful, outputOnly, metadataOnly, blank],
                                                               facetLimit: 2)

    expect(descriptors.map(\.id) == [
        "history-context-all",
        "history-context-action-总结",
        "history-context-model-gpt-4o-mini",
        "history-context-tag-项目A",
        "history-context-favorites"
    ], "history context commands include all/action/model/tag/favorite usable facets")
    expect(descriptors[0].subtitle == "2 条可用记录", "all context command counts usable history only")
    expect(descriptors[1].criteria == HistoryFilterCriteria(actionFilter: "总结"),
           "action context command carries action filter")
    expect(descriptors[2].criteria == HistoryFilterCriteria(modelFilter: "gpt-4o-mini"),
           "model context command carries model filter")
    expect(descriptors[3].criteria == HistoryFilterCriteria(tagFilter: "项目A"),
           "tag context command carries tag filter")
    expect(descriptors[4].subtitle == "1 条可用收藏记录",
           "favorite context command ignores metadata-only favorites")
    expect(!descriptors.contains { $0.title.contains("隐私审计") || $0.keywords.contains(PrivacyHistoryTag.metadataOnly) },
           "history context commands do not expose metadata-only records as context sources")

    expect(HistoryContextCommandFactory.descriptors(for: [metadataOnly, blank]).isEmpty,
           "history context commands are unavailable when no usable history content exists")

    let unsafe = HistoryEntry(actionName: "总结|`A`\n测试",
                              source: "项目背景",
                              output: "项目结论",
                              provider: "OpenAI",
                              model: "gpt|4o\nmini",
                              tags: ["项目|`A`\n标签"])
    let unsafeDescriptors = HistoryContextCommandFactory.descriptors(for: [unsafe], facetLimit: 4)
    let unsafeAction = unsafeDescriptors.first { $0.id.hasPrefix("history-context-action-") }
    let unsafeModel = unsafeDescriptors.first { $0.id.hasPrefix("history-context-model-") }
    let unsafeTag = unsafeDescriptors.first { $0.id.hasPrefix("history-context-tag-") }
    expect(unsafeAction?.title == "从总结/'A' 测试历史创建上下文",
           "history context action command keeps unsafe action names single-line")
    expect(unsafeAction?.criteria.actionFilter == "总结|`A` 测试",
           "history context action criteria keeps normalized original action value")
    expect(unsafeAction?.keywords.contains("\n") == false &&
           unsafeAction?.keywords.contains("|") == false &&
           unsafeAction?.keywords.contains("`") == false,
           "history context action command keywords are search-safe")
    expect(unsafeModel?.title == "从模型「gpt/4o mini」历史创建上下文",
           "history context model command keeps unsafe model names single-line")
    expect(unsafeModel?.criteria.modelFilter == "gpt|4o mini",
           "history context model criteria keeps normalized original model value")
    expect(unsafeModel?.keywords.contains("\n") == false &&
           unsafeModel?.keywords.contains("|") == false &&
           unsafeModel?.keywords.contains("`") == false,
           "history context model command keywords are search-safe")
    expect(unsafeTag?.title == "从标签「项目/'A' 标签」历史创建上下文",
           "history context tag command keeps unsafe tag names single-line")
    expect(unsafeTag?.criteria.tagFilter == "项目|`A` 标签",
           "history context tag criteria keeps normalized original tag value")
    expect(unsafeTag?.keywords.contains("\n") == false &&
           unsafeTag?.keywords.contains("|") == false &&
           unsafeTag?.keywords.contains("`") == false,
           "history context tag command keywords are search-safe")
}

func testHistoryExportCommandsUseDisplayTags() {
    let history = [
        HistoryEntry(actionName: " 总结 ",
                     source: "原文",
                     output: "结果",
                     provider: "OpenAI",
                     model: "gpt",
                     tags: [" 发布 ", "", "发布"]),
        HistoryEntry(actionName: "总结",
                     source: "hello",
                     output: "你好",
                     provider: "OpenAI",
                     model: "gpt",
                     tags: ["发布"]),
        HistoryEntry(actionName: " ",
                     source: "空动作历史",
                     output: "结果",
                     provider: "OpenAI",
                     model: " ",
                     tags: ["诊断"])
    ]

    let descriptors = HistoryExportCommandFactory.descriptors(for: history)
    let actionDescriptor = descriptors.first { $0.id == "history-copy-action-总结" }
    expect(actionDescriptor?.subtitle.hasPrefix("2 条记录") == true,
           "history export command counts normalized action names")
    expect(actionDescriptor?.criteria.actionFilter == "总结",
           "history export command filters by normalized action name")
    let unnamedActionDescriptor = descriptors.first { $0.id == "history-copy-action-未命名动作" }
    expect(unnamedActionDescriptor?.subtitle.hasPrefix("1 条记录") == true,
           "history export command exposes unnamed display action entries")
    expect(unnamedActionDescriptor?.criteria.actionFilter == "未命名动作",
           "history export command can filter unnamed display action entries")
    let modelDescriptor = descriptors.first { $0.id == "history-copy-model-gpt" }
    expect(modelDescriptor?.subtitle.hasPrefix("2 条记录") == true,
           "history export command counts normalized model names")
    expect(modelDescriptor?.criteria.modelFilter == "gpt",
           "history export command filters by normalized model name")
    let unknownModelDescriptor = descriptors.first { $0.id == "history-copy-model-未知模型" }
    expect(unknownModelDescriptor?.subtitle.hasPrefix("1 条记录") == true,
           "history export command exposes unknown model entries")
    expect(unknownModelDescriptor?.criteria.modelFilter == "未知模型",
           "history export command can filter unknown model entries")
    let tagDescriptor = descriptors.first { $0.id == "history-copy-tag-发布" }
    expect(tagDescriptor?.title == "复制标签「发布」历史",
           "history export command titles use normalized display tags")
    expect(tagDescriptor?.subtitle.hasPrefix("2 条记录") == true,
           "history export command counts deduped display tags per entry")
    expect(tagDescriptor?.criteria.tagFilter == "发布",
           "history export command filters by normalized display tag")
    expect(!descriptors.contains { $0.id.contains(" 发布 ") },
           "history export commands do not expose raw padded tags")

    let unsafeHistory = [
        HistoryEntry(actionName: "总结|`A`\n测试",
                     source: "原文",
                     output: "结果",
                     provider: "OpenAI",
                     model: "gpt|4o\nmini",
                     tags: ["项目|`A`\n标签"])
    ]
    let unsafeDescriptors = HistoryExportCommandFactory.descriptors(for: unsafeHistory, facetLimit: 4)
    let unsafeAction = unsafeDescriptors.first { $0.id.hasPrefix("history-copy-action-") }
    let unsafeModel = unsafeDescriptors.first { $0.id.hasPrefix("history-copy-model-") }
    let unsafeTag = unsafeDescriptors.first { $0.id.hasPrefix("history-copy-tag-") }
    expect(unsafeAction?.title == "复制总结/'A' 测试历史",
           "history export action command keeps unsafe action names single-line")
    expect(unsafeAction?.criteria.actionFilter == "总结|`A` 测试",
           "history export action criteria keeps normalized original action value")
    expect(unsafeAction?.keywords.contains("\n") == false &&
           unsafeAction?.keywords.contains("|") == false &&
           unsafeAction?.keywords.contains("`") == false,
           "history export action command keywords are search-safe")
    expect(unsafeModel?.title == "复制模型「gpt/4o mini」历史",
           "history export model command keeps unsafe model names single-line")
    expect(unsafeModel?.criteria.modelFilter == "gpt|4o mini",
           "history export model criteria keeps normalized original model value")
    expect(unsafeModel?.keywords.contains("\n") == false &&
           unsafeModel?.keywords.contains("|") == false &&
           unsafeModel?.keywords.contains("`") == false,
           "history export model command keywords are search-safe")
    expect(unsafeTag?.title == "复制标签「项目/'A' 标签」历史",
           "history export tag command keeps unsafe tag names single-line")
    expect(unsafeTag?.criteria.tagFilter == "项目|`A` 标签",
           "history export tag criteria keeps normalized original tag value")
    expect(unsafeTag?.keywords.contains("\n") == false &&
           unsafeTag?.keywords.contains("|") == false &&
           unsafeTag?.keywords.contains("`") == false,
           "history export tag command keywords are search-safe")
}

func testHistoryExportCommandFactoryBuildsRankedFacetCommands() {
    let entries = [
        HistoryEntry(actionName: "翻译",
                     source: "a",
                     output: "b",
                     provider: "OpenAI",
                     model: "gpt",
                     isFavorite: true,
                     tags: ["项目A", "发布"]),
        HistoryEntry(actionName: "翻译",
                     source: "c",
                     output: "d",
                     provider: "OpenAI",
                     model: "gpt",
                     tags: ["项目A"]),
        HistoryEntry(actionName: "总结",
                     source: "e",
                     output: "f",
                     provider: "OpenAI",
                     model: "gpt",
                     tags: ["  ", "诊断"])
    ]

    let descriptors = HistoryExportCommandFactory.descriptors(for: entries, facetLimit: 1)

    expect(descriptors.map(\.id) == [
        "history-copy-markdown",
        "history-copy-action-翻译",
        "history-copy-model-gpt",
        "history-copy-tag-项目A",
        "history-copy-favorites-markdown"
    ], "builds all/action/tag/favorite export commands in stable order")
    expect(descriptors[0].criteria == HistoryFilterCriteria(), "all history command uses default criteria")
    expect(descriptors[1].criteria == HistoryFilterCriteria(actionFilter: "翻译"), "action command filters by action")
    expect(descriptors[2].criteria == HistoryFilterCriteria(modelFilter: "gpt"), "model command filters by model")
    expect(descriptors[3].criteria == HistoryFilterCriteria(tagFilter: "项目A"), "tag command filters by tag")
    expect(descriptors[4].criteria == HistoryFilterCriteria(favoriteOnly: true), "favorite command filters favorites")
    expect(descriptors[1].subtitle == "2 条记录,Markdown", "action command reports count")
    expect(descriptors[2].keywords.contains("模型"), "model command is searchable by model")
    expect(descriptors[3].keywords.contains("项目A"), "tag command is searchable by tag")
    expect(HistoryExportCommandFactory.descriptors(for: []).isEmpty, "empty history produces no export commands")
}

func testHistoryExportCommandFactoryKeepsPrivacyTagsBeyondFacetLimit() {
    let entries = [
        HistoryEntry(actionName: "总结",
                     source: "a",
                     output: "b",
                     provider: "OpenAI",
                     model: "gpt",
                     tags: ["项目A"]),
        HistoryEntry(actionName: "总结",
                     source: "c",
                     output: "d",
                     provider: "OpenAI",
                     model: "gpt",
                     tags: ["项目B"]),
        HistoryEntry(actionName: "总结",
                     source: "e",
                     output: "f",
                     provider: "OpenAI",
                     model: "gpt",
                     tags: ["本地脱敏", "隐私预览", "隐私风险高", "隐私风险中", "仅元信息"])
    ]

    let descriptors = HistoryExportCommandFactory.descriptors(for: entries, facetLimit: 1)
    expect(descriptors.contains { $0.id == "history-copy-tag-本地脱敏" },
           "history export commands keep local redaction privacy tag beyond facet limit")
    expect(descriptors.contains { $0.id == "history-copy-tag-隐私预览" },
           "history export commands keep privacy preview tag beyond facet limit")
    expect(descriptors.contains { $0.id == "history-copy-tag-仅元信息" },
           "history export commands keep metadata-only privacy tag beyond facet limit")
    expect(descriptors.contains { $0.id == "history-copy-tag-隐私风险高" },
           "history export commands keep high privacy risk tag beyond facet limit")
    expect(descriptors.contains { $0.id == "history-copy-tag-隐私风险中" },
           "history export commands keep medium privacy risk tag beyond facet limit")
    expect(descriptors.first { $0.id == "history-copy-tag-本地脱敏" }?.criteria.tagFilter == "本地脱敏",
           "privacy tag export command filters by privacy tag")
    expect(descriptors.first { $0.id == "history-copy-tag-隐私风险高" }?.criteria.tagFilter == "隐私风险高",
           "high privacy risk export command filters by privacy risk tag")
    expect(descriptors.first { $0.id == "history-copy-tag-仅元信息" }?.criteria.tagFilter == "仅元信息",
           "metadata-only privacy tag export command filters by privacy tag")
}

func testHistoryExportCommandIDsAreStableSlugs() {
    let entries = [
        HistoryEntry(actionName: "A/B",
                     source: "a",
                     output: "b",
                     provider: "OpenAI",
                     model: "gpt/4o mini",
                     tags: ["项目/Alpha"]),
        HistoryEntry(actionName: "A B",
                     source: "c",
                     output: "d",
                     provider: "OpenAI",
                     model: "gpt 4o mini",
                     tags: ["项目 Alpha"])
    ]

    let descriptors = HistoryExportCommandFactory.descriptors(for: entries, facetLimit: 4)
    let actionIDs = descriptors
        .filter { $0.id.hasPrefix("history-copy-action-") }
        .map(\.id)
    expect(actionIDs.contains("history-copy-action-A-B"), "history export action ids replace separators with slug dashes")
    expect(actionIDs.contains("history-copy-action-A-B-2"), "history export action ids disambiguate slug collisions")
    expect(descriptors.contains { $0.id == "history-copy-model-gpt-4o-mini" },
           "history export model ids replace slash and spaces")
    expect(descriptors.contains { $0.id == "history-copy-model-gpt-4o-mini-2" },
           "history export model ids disambiguate model slug collisions")
    expect(descriptors.contains { $0.id == "history-copy-tag-项目-Alpha" },
           "history export tag ids keep readable unicode and replace separators")
    expect(descriptors.contains { $0.id == "history-copy-tag-项目-Alpha-2" },
           "history export tag ids disambiguate tag slug collisions")
    expect(descriptors.allSatisfy { !$0.id.contains("/") && !$0.id.contains(" ") },
           "history export command ids do not contain path or whitespace separators")
}

func testConversationExportMarkdown() {
    let export = ConversationExport(actionName: "润色",
                                    sourceText: "原文",
                                    outputText: "润色结果",
                                    providerName: "OpenAI",
                                    modelName: "gpt-4o-mini",
                                    elapsed: 1.25,
                                    diagnostics: "route ok",
                                    date: Date(timeIntervalSince1970: 0))
    let markdown = export.markdown
    expect(markdown.contains("# 润色"), "exports action title")
    expect(markdown.contains("## 原文\n\n原文"), "exports source section")
    expect(markdown.contains("## 结果\n\n润色结果"), "exports output section")
    expect(markdown.contains("*模型: OpenAI / gpt-4o-mini | 耗时: 1.2s*"), "exports model and elapsed")
    expect(markdown.contains("## 诊断"), "includes diagnostics section")
    expect(markdown.contains("route ok"), "includes diagnostics text")

    let unsafeDiagnostics = """
    route failed
    Authorization: Bearer sk-live-secret-value-1234567890
    log: /Users/alice/Library/Logs/snapai.log
    ```
    """
    let unsafeExport = ConversationExport(actionName: "润色\n换行",
                                          sourceText: "原文",
                                          outputText: "结果",
                                          providerName: "OpenAI",
                                          modelName: "gpt-4o-mini",
                                          elapsed: 0.5,
                                          diagnostics: unsafeDiagnostics,
                                          date: Date(timeIntervalSince1970: 0))
    let unsafeMarkdown = unsafeExport.markdown
    expect(unsafeMarkdown.contains("# 润色 换行"), "conversation export keeps headings single-line")
    expect(!unsafeMarkdown.contains("sk-live-secret-value-1234567890"), "conversation export redacts diagnostic secrets")
    expect(!unsafeMarkdown.contains("/Users/alice"), "conversation export redacts diagnostic user paths")
    expect(unsafeMarkdown.contains("/Users/[user]/Library/Logs/snapai.log"),
           "conversation export keeps useful diagnostic path suffix")
    expect(unsafeMarkdown.contains("````text"), "conversation export expands diagnostic code fence when needed")

    let protectedExport = ConversationExport(actionName: "提问",
                                             sourceText: "联系 test@example.com",
                                             outputText: "结果包含 sk-live-secret-value-1234567890",
                                             providerName: "OpenAI",
                                             modelName: "gpt-4o-mini",
                                             elapsed: 0.5,
                                             diagnostics: "Privacy Risk: high",
                                             protectsContent: true,
                                             date: Date(timeIntervalSince1970: 0))
    let protectedMarkdown = protectedExport.markdown
    expect(protectedMarkdown.contains("## 隐私保护"),
           "protected conversation export explains why content is omitted")
    expect(protectedMarkdown.contains("因高风险隐私保护,未导出原文。"),
           "protected conversation export replaces source text")
    expect(protectedMarkdown.contains("因高风险隐私保护,未导出结果。"),
           "protected conversation export replaces output text")
    expect(!protectedMarkdown.contains("test@example.com"),
           "protected conversation export omits sensitive source")
    expect(!protectedMarkdown.contains("sk-live-secret-value-1234567890"),
           "protected conversation export omits sensitive output")
    expect(protectedMarkdown.contains("Privacy Risk: high"),
           "protected conversation export still includes safe diagnostics")
}

testVersionNormalizationAndCompare()
testReleaseTagParsing()
testReleaseAssetSelectionUsesExactVersionedNames()
testGitHubAssetDigestValidation()
testChecksumSourceRequiresDigestOrManifest()
testReleaseManifestValidation()
testLatestInstallLogURLValidation()
testInstallLogCommandSubtitleRedactsUserPaths()
testDesignatedRequirementParsing()
testPermissionDiagnosticsFormatting()
testPermissionDiagnosticsReportsAPIKeyHealth()
testPermissionDiagnosticsReportsWorkMode()
testPermissionDiagnosticsReportsRequestReadiness()
testBaseURLNormalization()
testAIClientEffectiveRuntimeParametersAreSanitized()
testAIClientStreamErrorParsing()
testAIClientResponseErrorBodySanitization()
testPromptRender()
testActionPipelineDiagnostic()
testAIActionSanitizesImportedConfiguration()
testDefaultPolishActionConfirmsReplacement()
testTextReplacementSelectionDelay()
testScreenCaptureTemporaryFileUsesUniqueUnpredictablePath()
testScreenCapturePermissionPreflightAndRecoveryMessage()
testScreenCaptureFailureDiagnosticsAreShareableAndPathFree()
testScreenCaptureFailureDiagnosticsDescribeOutputProblems()
testWriteBackUndoRecordAvailability()
testWriteBackFallbackDiagnosticSummarizesFailureWithoutContent()
testWriteBackUndoFallbackDiagnosticSummarizesFailureWithoutContent()
testWriteBackCommandFactoryReflectsUndoAvailability()
testCapturedTextPreservesSelectionWhitespace()
testTextCaptureRecoveryGuidePointsToActionablePermissionHelp()
testTextCaptureDiagnosticSummarizesStateWithoutContent()
testSystemPrivacySettingsBuildsStablePaneURLs()
testPasteboardRestoreDecisionProtectsUserChanges()
testTextCaptureValidatesAXCoreFoundationTypes()
testHotKeyConflictDetection()
testCommandPaletteMatchesMultipleTerms()
testCommandPaletteRanksMatchesByRelevance()
testCommandPaletteSearchesShortcutTextAliases()
testCommandIdentifierSlugAndUniqueness()
testModelSwitchCommandFactoryFiltersAndMarksCurrentModel()
testModelSwitchCommandIDsAreStableSlugs()
testActionCommandFactoryFiltersAndFormatsActions()
testActionCommandFactoryPrioritizesFrequentActions()
testActionCommandIDsAreStableSlugs()
testAutomationActionSelectionNormalizesQueries()
testAutomationSettingsSectionSelectionNormalizesQueries()
testAutomationURLCommandParsing()
testAutomationWriteBackPolicyRequiresCapturedSelection()
testAutomationRunOptionsApplyToActionWithoutChangingSettings()
testAutomationModelSelectionResolvesEnabledModelsOnly()
testAutomationContextSelectionRequiresEnabledNonEmptyProfile()
testAutomationContextClearRestoresBasePrompt()
testAutomationRoutingPreferenceSelectionResolvesAliases()
testAutomationWorkModeSelectionResolvesAliases()
testAutomationTypewriterSpeedSelectionResolvesAliases()
testAIRouterIncludesFallbackCandidates()
testAIRequestDiagnosticsSummary()
testAIRequestPayloadDiagnosticEstimatesRequestShape()
testAIRequestPayloadDiagnosticReportsContextFit()
testAIRequestDiagnosticsReportsCandidateImageFit()
testAIRequestDiagnosticsReportsCandidateReasoningFit()
testAIRequestDiagnosticsReportsCandidateFitIssueSummary()
testAIRequestDiagnosticsReportsRecommendedRouteSafely()
testAIRequestDiagnosticsReportsRecommendedRouteIssues()
testAIRequestDiagnosticsReportsFirstRequestRouteAfterSkips()
testAIRequestDiagnosticsBuildsRouteDisplayNotesWithIssues()
testAIRequestDiagnosticsAnnotatesAttemptsWithRouteIssues()
testAIRequestDiagnosticsSkipsHardIncompatibleRoutes()
testAIRequestFallbackDecisionExplainsSkippedFallbacks()
testVisibleErrorRecoverySuggestionText()
testAIRequestDiagnosticsClassifiesCommonErrorRecoverySuggestions()
testNoCandidateRouteDiagnosticsExplainProviderReadiness()
testAIRequestAttemptDiagnosticFormatsDurations()
testSensitiveTextSanitizerRedactsSensitiveErrorFragments()
testAIRequestDiagnosticsUsesSensitiveTextSanitizer()
testAIRequestDiagnosticsSanitizesRouteMetadata()
testAIRequestRouteDisplayNotesAreSanitized()
testAIRouterSkipsDisabledActionOverrideModel()
testAIRouterSkipsDisabledActiveModel()
testAIRouterScopedSettingsRequiresEnabledRouteModel()
testAIRouterProviderRequestReadiness()
testAIRouterFallbackSkipsProvidersThatCannotRequest()
testAIRouterKeepsActiveProviderWhenNotRequestReady()
testSettingsModelClearsWhenActiveProviderHasNoEnabledModels()
testPermissionDiagnosticsUsesSafeActiveModelSummary()
testModelCapabilityInference()
testAIRouterUsesCapabilityReasonForCodeAction()
testAIRouterUsesFullRequestSizeForLongContextRouting()
testAIRouterDemotesOverLimitModelsWhenAutoRouting()
testAIRouterPromotesVisionModelForImageRequests()
testAIRouterPromotesReasoningModelForThinkingActions()
testAIRouterUsesRoutingPreferenceForFallbackOrder()
testAIRouterUsesRoutingPreferenceWhenOnlyFallbackIsEnabled()
testAIRouterPrefersLocalModelRoutesInPrivacyMode()
testAIRouterUsesStableConfiguredOrderForEqualScores()
testPrivacyRedactionDefaults()
testPrivacyRedactionDefaultSampleDemonstratesSensitiveFormats()
testPrivacyRedactionPreviewReportsInvalidRules()
testPrivacyRedactionGuardsRiskyRulesAndLongReplacement()
testPrivacySubmissionPreviewExplainsFinalPayload()
testPrivacySubmissionPreviewReportsRiskWhenRedactionDisabled()
testPrivacySubmissionPreviewRequirementProtectsHighRiskPayloads()
testPrivacySubmissionPreviewReportsInvalidRules()
testPrivacyHistoryTagExportPriorityIncludesMetadataOnly()
testAppSettingsAddHistoryPersistsPrivacyTags()
testAppSettingsAddHistoryCanStoreMetadataOnly()
testAppSettingsAddHistoryCanOverrideStorageForOneEntry()
testAppSettingsAddHistoryTruncatesLargeContentAndTags()
testAppSettingsUpdateHistoryTagsSanitizesManualTags()
testSettingsDecodeSanitizesStoredHistory()
testSettingsClampsStoredPanelDimensions()
testPrivacySubmissionPreviewCanRepresentFollowUpPayload()
testPrivacySubmissionPreviewRendersSourceResendPayload()
testTextDiffSummary()
testTextDiffCapsLargePreviewRows()
testContextProfileEffectiveSystemPrompt()
testSettingsCodablePreservesRoutingAndHistoryPreferences()
testSettingsExportConfigurationOmitsSecretsAndHistory()
testSettingsSanitizesStoredActionUsageCounts()
testSettingsRecordActionUsageUsesSafeBounds()
testSettingsImportProvidersIgnorePlaintextKeys()
testSettingsImportProvidersSanitizeRuntimeBoundaries()
testSettingsImportRemapsActionProviderOverridesAfterProviderIDRepair()
testSettingsDecodeSanitizesStoredProviders()
testSettingsDecodeSanitizesStoredRedactionRules()
testSettingsLoadPersistsMigratedLegacyRedactionRules()
testSettingsImportSanitizesUnsafeConfiguration()
testSettingsDecodeSanitizesStoredContextProfiles()
testSettingsDecodeSanitizesStoredPrompts()
testSettingsDecodeDefaultsRoutingPreference()
testSettingsDecodeDefaultsActiveProviderToFirstProvider()
testSettingsNormalizeActiveSkipsDisabledProviderAndModel()
testSettingsNormalizeActiveClearsWhenNoEnabledProviderExists()
testCloudSettingsPayloadPreservesRoutingPreferenceAndNormalizesModel()
testCloudSettingsPayloadRemapsActiveProviderAfterProviderIDRepair()
testCloudSettingsPayloadDecodeRemapsActionsAfterProviderIDRepair()
testWorkModePresetsApplyCoherentSettings()
testWorkModeCommandFactoryReflectsCurrentState()
testSettingsToggleCommandReflectsCurrentState()
testSettingsToggleCommandResolvesAliasesAndSetsState()
testSettingsWindowPinCommandReflectsCurrentState()
testResultPinCommandReflectsCurrentState()
testDisplayBehaviorCommandFactoryReflectsCurrentState()
testRoutingContextCommandFactoryReflectsCurrentState()
testResultDiagnosticsCommandIsSearchable()
testResultRecoveryCommandPointsToAISettings()
testFollowUpInputBehaviorSupportsMultilineDrafts()
testFollowUpHistoryStoreNavigatesRecentPromptsSafely()
testResultCommandFactoryHidesCommandsWithoutResultContext()
testResultCommandStateBuildsFromResultTexts()
testResultCommandFactoryBuildsStableMenuCommands()
testResultCommandFactoryExplainsProtectedConversationExports()
testResultCommandFactoryAdaptsAISettingsRecoveryCommand()
testResultCommandFactoryAdaptsRetryRecoveryCommand()
testResultCommandFactoryIncludesResultWriteBackAndRegenerateCommands()
testResultCommandFactoryUsesStopWhileStreaming()
testResultCommandFactoryOmitsDiagnosticsWhenUnavailable()
testResultCommandFactoryShowsRecoverySettingsWithoutDiagnostics()
testHistoryEntryMarkdownExport()
testHistoryEntryCompactTitlesForMenus()
testHistoryEntryCommandPaletteKeywordsCoverMetadata()
testHistoryFilterCriteriaMatchesMultipleTermsAndFacets()
testHistoryFilterCriteriaMatchesDisplayFallbacks()
testHistoryCollectionExportMarkdown()
testHistoryContextProfileBuilderCreatesSafeContextDraft()
testHistoryContextProfileBuilderSanitizesMetadata()
testAppSettingsUpsertsHistoryContextProfileByName()
testHistoryContextCommandFactoryBuildsUsableContextCommands()
testHistoryExportCommandsUseDisplayTags()
testHistoryExportCommandFactoryBuildsRankedFacetCommands()
testHistoryExportCommandFactoryKeepsPrivacyTagsBeyondFacetLimit()
testHistoryExportCommandIDsAreStableSlugs()
testConversationExportMarkdown()

if failures.isEmpty {
    print("SnapAILogicTests passed")
} else {
    print("SnapAILogicTests failed:")
    failures.forEach { print("- \($0)") }
    exit(1)
}
