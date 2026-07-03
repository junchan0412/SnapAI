import Foundation
import AppKit
import ApplicationServices
import Carbon.HIToolbox

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
            asset("snapai-manifest-v1.2.0.json"),
            asset("snapai-manifest-v1.2.0.json.sig")
        ]
    )

    expect(release.appZipAsset?.name == "SnapAI-v1.2.0.zip",
           "release asset selection chooses the exact app zip for the release tag")
    expect(release.manifestAsset?.name == "snapai-manifest-v1.2.0.json",
           "release asset selection chooses the exact manifest for the release tag")
    expect(release.manifestSignatureAsset?.name == "snapai-manifest-v1.2.0.json.sig",
           "release asset selection chooses the exact manifest signature for the release tag")
    expect(release.expectedAppZipAssetName == "SnapAI-v1.2.0.zip",
           "release asset selection exposes the expected app zip name")
    expect(release.expectedManifestAssetName == "snapai-manifest-v1.2.0.json",
           "release asset selection exposes the expected manifest name")
    expect(release.expectedManifestSignatureAssetName == "snapai-manifest-v1.2.0.json.sig",
           "release asset selection exposes the expected manifest signature name")

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
            asset("snapai-manifest-v1.2.0.json"),
            asset("snapai-manifest-v1.2.0.json.sig")
        ]
    )
    expect(bareTagRelease.appZipAsset?.name == "SnapAI-v1.2.0.zip",
           "release asset selection normalizes bare numeric release tags")
    expect(bareTagRelease.manifestAsset?.name == "snapai-manifest-v1.2.0.json",
           "release manifest selection normalizes bare numeric release tags")
    expect(bareTagRelease.manifestSignatureAsset?.name == "snapai-manifest-v1.2.0.json.sig",
           "release manifest signature selection normalizes bare numeric release tags")

    let fallbackRelease = UpdateChecker.webFallbackRelease(tagName: "1.2.0")
    expect(fallbackRelease.appZipAsset?.name == "SnapAI-v1.2.0.zip",
           "web fallback release includes the exact app zip asset")
    expect(fallbackRelease.manifestAsset?.name == "snapai-manifest-v1.2.0.json",
           "web fallback release includes the exact manifest asset")
    expect(fallbackRelease.manifestSignatureAsset?.name == "snapai-manifest-v1.2.0.json.sig",
           "web fallback release includes the exact manifest signature asset")
    expect(fallbackRelease.assets.count == 3,
           "web fallback release constructs install, manifest, and signature assets")

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

    let missingSignatureRelease = UpdateChecker.Release(
        tagName: "v1.2.0",
        name: nil,
        htmlURL: URL(string: "https://github.com/junchan0412/SnapAI/releases/tag/v1.2.0")!,
        assets: [
            asset("SnapAI-v1.2.0.zip"),
            asset("snapai-manifest-v1.2.0.json")
        ]
    )
    do {
        _ = try UpdateChecker.requiredManifestSignatureAsset(for: missingSignatureRelease,
                                                             assetName: "snapai-manifest-v1.2.0.json")
        expect(false, "missing manifest signature fails release metadata validation")
    } catch {
        expect(error.localizedDescription.contains("签名文件 snapai-manifest-v1.2.0.json.sig"),
               "missing manifest signature error names the expected signature asset")
    }

    let duplicateSignatureRelease = UpdateChecker.Release(
        tagName: "v1.2.0",
        name: nil,
        htmlURL: URL(string: "https://github.com/junchan0412/SnapAI/releases/tag/v1.2.0")!,
        assets: [
            asset("SnapAI-v1.2.0.zip"),
            asset("snapai-manifest-v1.2.0.json"),
            asset("snapai-manifest-v1.2.0.json.sig"),
            asset("snapai-manifest-v1.2.0.json.sig")
        ]
    )
    do {
        _ = try UpdateChecker.requiredManifestSignatureAsset(for: duplicateSignatureRelease,
                                                             assetName: "snapai-manifest-v1.2.0.json")
        expect(false, "duplicate manifest signatures fail release metadata validation")
    } catch {
        expect(error.localizedDescription.contains("重复资产 snapai-manifest-v1.2.0.json.sig"),
               "duplicate manifest signature error names the ambiguous asset")
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

func testReleaseManifestSigningAndSignatureValidation() {
    let assetName = "SnapAI-v1.2.0.zip"
    let sha = String(repeating: "0", count: 64)
    let requirement = #"identifier "com.snapai.app" and certificate leaf = H"547f9e9ccbac459f1ae9db2644e819edeb2e766e""#
    let signing = UpdateChecker.ReleaseManifest.Signing(
        designatedRequirement: requirement,
        certificateFingerprintSHA1: "547F9E9CCBAC459F1AE9DB2644E819EDEB2E766E"
    )
    let manifest = UpdateChecker.ReleaseManifest(
        version: "v1.2.0",
        bundleIdentifier: "com.snapai.app",
        signing: signing,
        assets: [
            UpdateChecker.ReleaseManifest.ManifestAsset(name: assetName, sha256: sha)
        ]
    )
    let validatedSigning = try? UpdateChecker.validatedManifestSigning(
        from: manifest,
        expectedBundleID: "com.snapai.app",
        expectedDesignatedRequirement: requirement
    )
    expect(validatedSigning == signing,
           "validates manifest bundle id and designated requirement")
    expect(UpdateChecker.normalizedSHA1(" 547F9E9CCBAC459F1AE9DB2644E819EDEB2E766E\n") == "547f9e9ccbac459f1ae9db2644e819edeb2e766e",
           "normalizes uppercase SHA1 certificate fingerprints")
    expect(UpdateChecker.normalizedSHA1(String(repeating: "g", count: 40)) == nil,
           "rejects non-hex SHA1 certificate fingerprints")

    func signingError(_ manifest: UpdateChecker.ReleaseManifest,
                      bundleID: String = "com.snapai.app",
                      requirement: String = requirement) -> String {
        do {
            _ = try UpdateChecker.validatedManifestSigning(from: manifest,
                                                           expectedBundleID: bundleID,
                                                           expectedDesignatedRequirement: requirement)
            return ""
        } catch {
            return error.localizedDescription
        }
    }

    let missingBundle = UpdateChecker.ReleaseManifest(version: "v1.2.0",
                                                      signing: signing,
                                                      assets: manifest.assets)
    expect(signingError(missingBundle).contains("缺少 bundleIdentifier"),
           "rejects manifests without a bundle id")

    let mismatchedBundle = UpdateChecker.ReleaseManifest(version: "v1.2.0",
                                                         bundleIdentifier: "com.other.app",
                                                         signing: signing,
                                                         assets: manifest.assets)
    expect(signingError(mismatchedBundle).contains("bundleIdentifier"),
           "rejects manifests whose bundle id differs from the current app")

    let missingSigning = UpdateChecker.ReleaseManifest(version: "v1.2.0",
                                                       bundleIdentifier: "com.snapai.app",
                                                       assets: manifest.assets)
    expect(signingError(missingSigning).contains("缺少签名身份信息"),
           "rejects manifests without signing identity metadata")

    let badFingerprint = UpdateChecker.ReleaseManifest(
        version: "v1.2.0",
        bundleIdentifier: "com.snapai.app",
        signing: UpdateChecker.ReleaseManifest.Signing(
            designatedRequirement: requirement,
            certificateFingerprintSHA1: "1234"
        ),
        assets: manifest.assets
    )
    expect(signingError(badFingerprint).contains("certificateFingerprintSHA1 格式无效"),
           "rejects malformed certificate fingerprints")

    let manifestJSON = #"{"version":"v1.2.0","assets":[{"name":"SnapAI-v1.2.0.zip","sha256":"0000000000000000000000000000000000000000000000000000000000000000"}]}"#
    let publicKey = """
    -----BEGIN PUBLIC KEY-----
    MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAidXV39jpDaUp39k6chin
    zPA3sYFuF10X1vvSU/xtK/KZmIMbrhROM2LP31zRjQ0yhDEElNe//lS0GhOqv7hJ
    JmmAQDPyCLEutKxsY1PktkhsBNeT3D8nDsNAnPrJrZ7yTWIdmkR5C32tI8tZIK55
    m97VcnxDeZNImN+rShHNWrkJAajcVALIVevSmiTUTu8GmYMIk/MwGFes+Ztsqp1m
    yi0FQDyTD6hoCwmkY42byNnFrpSWShsfWkzzFktojGIQuiOTUcQIAPrATb/Ay61A
    84jhyyZ1SdSygABHCqHWdGEgwGtXtS6uU/jEFKAR9G0/JJ64SHfeJ8ieqg1VmkdB
    1QIDAQAB
    -----END PUBLIC KEY-----
    """
    let signature = Data(base64Encoded: "Wg9Qz9j10a3HtYiCe9l3CNtO9Vyz93fZixoYTouHmA7Uc5gSgGs9vZNEAArjWqOI4uGwMo1qyagZSss8ufrLCw27YgXYhdaKngi4yovwnyQLMXp5640IVgmxEzlnMwehVIpsl/9DKG7HdV7LSEuKPqSasJiUJWUW/i59x8zI5xX2QmPMu8OZtuNkjnG0OxZkNj0L85aJ/azNVoxyHBpAqjOZkEjePInaQuZtc4mxWaZpfH9Hdi4eU3X0ZJ5E3Pirm+prN3LUXx43b8B5B54F0jUdVghe2oF0oJcmChPvf4cNc9e8oSyNPRZX/xZptPExD7lZcJ993tSWGvfmnbCdlg==")!
    do {
        try UpdateChecker.verifyManifestSignature(manifestData: Data(manifestJSON.utf8),
                                                  signatureData: signature,
                                                  publicKeyPEM: publicKey)
    } catch {
        expect(false, "valid manifest signature verifies: \(error.localizedDescription)")
    }
    do {
        try UpdateChecker.verifyManifestSignature(manifestData: Data((manifestJSON + " ").utf8),
                                                  signatureData: signature,
                                                  publicKeyPEM: publicKey)
        expect(false, "tampered manifest signature fails verification")
    } catch {
        expect(error.localizedDescription.contains("Release manifest 签名无法验证"),
               "tampered manifest reports signature verification failure")
    }
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
