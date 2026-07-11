import CryptoKit
import Foundation

public enum UpdateChecker {
    private static let repositoryURL = URL(string: "https://github.com/junchan0412/SnapAI")!
    private static let latestReleaseAPIURL = URL(string: "https://api.github.com/repos/junchan0412/SnapAI/releases/latest")!
    private static let latestReleasePageURL = URL(string: "https://github.com/junchan0412/SnapAI/releases/latest")!
    private static let latestInstallLogKey = "SnapAI.UpdateChecker.latestInstallLogPath"
    private static let manifestPublicKeyResourceName = "ManifestPublicKey"
    private static let embeddedManifestPublicKeyPEM = """
    -----BEGIN PUBLIC KEY-----
    MIIBojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEA6V7iUMZyADSXO9CCtysa
    rkUAXplF9dy7YtYKcbK8av5f0ChnwKiJFGwA5oTnIoOMnJC6Mzp/F40NbMVhJVm1
    Si/L3DnDanmIeFZ6xZ7aGHImBfolJ4ijvPwnu6iABblDiBrPXqXqnw3THa2dKf0Z
    St3fo2SL3SKXQL/sT2FrgUnf0e2hMgQ9dRW0EDhhkOaKILVHBTRpfqIrOWDxB7ii
    Bw2j4KGLEZ6ORddPsyRw0C3c86HrMu3HAfGtHEXdd8Kds13VhAGLRhwpAiiQRa5r
    JXFupsMilqY83klud0zySkK2/PLwLWoLQoW8DPcbDf7fbODkQLI3D1rkzZ884Gm7
    jbGUwTlVpSS1VFuix2FL2VF7NKBY2KK3qsA/NMA1LrLcKkusykHxoB2XbcG66lzr
    qdPmyKL6A0BnHtuNFi2xJN0Gof49HEjIfPYmWb4tnltGylsSlnQLuk3Kqrhnt2Kg
    SQiGk9c798Ua589neEDBGM37s+8sFQtprq96/Ey4ShxTAgMBAAE=
    -----END PUBLIC KEY-----
    """

    public struct Release: Decodable {
        public let tagName: String
        public let name: String?
        public let htmlURL: URL
        public let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name
            case htmlURL = "html_url"
            case assets
        }

        public var appZipAsset: Asset? {
            uniqueAsset(named: expectedAppZipAssetName)
        }

        public var manifestAsset: Asset? {
            uniqueAsset(named: expectedManifestAssetName)
        }

        public var manifestSignatureAsset: Asset? {
            uniqueAsset(named: expectedManifestSignatureAssetName)
        }

        public var expectedAppZipAssetName: String {
            "SnapAI-\(versionedTag).zip"
        }

        public var expectedManifestAssetName: String {
            "snapai-manifest-\(versionedTag).json"
        }

        public var expectedManifestSignatureAssetName: String {
            "\(expectedManifestAssetName).sig"
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

    public struct Asset: Decodable {
        public let name: String
        public let browserDownloadURL: URL
        public let digest: String?

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
            case digest
        }
    }

    public struct ReleaseManifest: Decodable {
        public struct ManifestAsset: Decodable {
            public let name: String
            public let sha256: String

            public init(name: String, sha256: String) {
                self.name = name
                self.sha256 = sha256
            }
        }

        public struct Signing: Decodable, Equatable {
            public let designatedRequirement: String
            public let certificateFingerprintSHA1: String

            public init(designatedRequirement: String,
                 certificateFingerprintSHA1: String) {
                self.designatedRequirement = designatedRequirement
                self.certificateFingerprintSHA1 = certificateFingerprintSHA1
            }
        }

        public let version: String?
        public let bundleIdentifier: String?
        public let signing: Signing?
        public let assets: [ManifestAsset]

        public init(version: String?,
             bundleIdentifier: String? = nil,
             signing: Signing? = nil,
             assets: [ManifestAsset]) {
            self.version = version
            self.bundleIdentifier = bundleIdentifier
            self.signing = signing
            self.assets = assets
        }
    }

    public enum InstallLogStatus: Equatable {
        case noRecord
        case untrustedLocation(String)
        case missing(String)
        case available(URL)

        public var diagnosticCode: String {
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

        public var diagnosticPath: String {
            switch self {
            case .noRecord:
                return "none"
            case .untrustedLocation(let path), .missing(let path):
                return path
            case .available(let url):
                return url.path
            }
        }

        public var recoverySuggestion: String {
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

        public var url: URL? {
            switch self {
            case .available(let url):
                return url
            case .noRecord, .untrustedLocation, .missing:
                return nil
            }
        }
    }

    public enum UpdateError: LocalizedError {
        case noInstallAsset
        case downloadFailed(Int)
        case invalidArchive
        case bundleMismatch
        case installLocationNotWritable(String)
        case releaseLookupFailed(primary: Error, fallback: Error)
        case checksumMismatch(expected: String, actual: String)
        case invalidManifest(String)
        case invalidManifestSignature(String)
        case invalidReleaseMetadata(String)
        case signingIdentityChanged(current: String, incoming: String)
        case signingRequirementUnavailable(String)

        public var errorDescription: String? {
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
            case .invalidManifestSignature(let message):
                return "Release manifest 签名无法验证:\n\(SensitiveTextSanitizer.sanitizedMessage(message))"
            case .invalidReleaseMetadata(let message):
                return "Release 元数据无法验证:\n\(SensitiveTextSanitizer.sanitizedMessage(message))"
            case .signingIdentityChanged(let current, let incoming):
                return """
                更新包的签名身份与当前 SnapAI 不一致,已取消自动安装。

                这通常会导致辅助功能等系统授权在更新后重新询问。请确认发布包继续使用同一个稳定签名证书。

                当前: \(current)
                新包: \(incoming)
                """
            case .signingRequirementUnavailable(let path):
                return "无法读取应用签名要求,已取消自动安装:\n\(path)"
            }
        }
    }
    public static func webFallbackRelease(tagName: String) -> Release {
        let htmlURL = releaseTagURL(tagName)
        let versionedTag = versionedReleaseTag(tagName)
        let appAssetName = "SnapAI-\(versionedTag).zip"
        let manifestAssetName = "snapai-manifest-\(versionedTag).json"
        let manifestSignatureAssetName = "\(manifestAssetName).sig"
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
                ),
                Asset(
                    name: manifestSignatureAssetName,
                    browserDownloadURL: releaseDownloadURL(tagName: tagName, assetName: manifestSignatureAssetName),
                    digest: nil
                )
            ]
        )
    }

    public static func requiredManifestAsset(for release: Release, assetName: String) throws -> Asset {
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

    public static func requiredManifestSignatureAsset(for release: Release, assetName: String) throws -> Asset {
        let matches = release.assets(named: release.expectedManifestSignatureAssetName)
        guard matches.count == 1, let signatureAsset = matches.first else {
            if matches.isEmpty {
                throw UpdateError.invalidReleaseMetadata(
                    "\(assetName) 缺少已签名 manifest 的签名文件 \(release.expectedManifestSignatureAssetName)。"
                )
            }
            throw UpdateError.invalidReleaseMetadata(
                "Release 中存在重复资产 \(release.expectedManifestSignatureAssetName),已取消自动安装。"
            )
        }
        return signatureAsset
    }

    public static func requiredAppZipAsset(for release: Release) throws -> Asset {
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

    public static func validatedGitHubDigestSHA256(_ digest: String?) throws -> String? {
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

    public static func validatedManifestSHA256(from manifest: ReleaseManifest,
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

    @discardableResult
    public static func validatedManifestSigning(from manifest: ReleaseManifest,
                                         expectedBundleID: String,
                                         expectedDesignatedRequirement: String) throws -> ReleaseManifest.Signing {
        guard let bundleIdentifier = manifest.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !bundleIdentifier.isEmpty else {
            throw UpdateError.invalidManifest("manifest 缺少 bundleIdentifier。")
        }
        guard bundleIdentifier == expectedBundleID else {
            throw UpdateError.invalidManifest("manifest bundleIdentifier \(bundleIdentifier) 与当前应用 \(expectedBundleID) 不一致。")
        }
        guard let signing = manifest.signing else {
            throw UpdateError.invalidManifest("manifest 缺少签名身份信息。")
        }
        let requirement = signing.designatedRequirement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !requirement.isEmpty else {
            throw UpdateError.invalidManifest("manifest designatedRequirement 为空。")
        }
        guard requirement == expectedDesignatedRequirement else {
            throw UpdateError.invalidManifest("manifest designatedRequirement 与当前应用不一致。")
        }
        guard normalizedSHA1(signing.certificateFingerprintSHA1) != nil else {
            throw UpdateError.invalidManifest("manifest certificateFingerprintSHA1 格式无效。")
        }
        return signing
    }

    public static func verifyManifestSignature(manifestData: Data,
                                        signatureData: Data,
                                        publicKeyPEM: String = bundledManifestPublicKeyPEM()) throws {
        guard !manifestData.isEmpty else {
            throw UpdateError.invalidManifestSignature("manifest 为空。")
        }
        guard !signatureData.isEmpty else {
            throw UpdateError.invalidManifestSignature("manifest 签名为空。")
        }
        let publicKey = publicKeyPEM.trimmingCharacters(in: .whitespacesAndNewlines)
        guard publicKey.contains("BEGIN PUBLIC KEY") else {
            throw UpdateError.invalidManifestSignature("内置 manifest 公钥不可用。")
        }

        let verifyDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SnapAIManifestVerify-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: verifyDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: verifyDir) }

        let manifestURL = verifyDir.appendingPathComponent("manifest.json")
        let signatureURL = verifyDir.appendingPathComponent("manifest.sig")
        let publicKeyURL = verifyDir.appendingPathComponent("manifest.pub")
        try manifestData.write(to: manifestURL, options: .atomic)
        try signatureData.write(to: signatureURL, options: .atomic)
        try publicKey.write(to: publicKeyURL, atomically: true, encoding: .utf8)

        do {
            try runTool("/usr/bin/openssl", arguments: [
                "dgst",
                "-sha256",
                "-verify", publicKeyURL.path,
                "-signature", signatureURL.path,
                manifestURL.path
            ])
        } catch {
            throw UpdateError.invalidManifestSignature(error.localizedDescription)
        }
    }

    public static func normalizedSHA256(_ value: String) -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hexCharacters = CharacterSet(charactersIn: "0123456789abcdef")
        guard normalized.count == 64,
              normalized.unicodeScalars.allSatisfy({ hexCharacters.contains($0) }) else {
            return nil
        }
        return normalized
    }

    public static func normalizedSHA1(_ value: String) -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hexCharacters = CharacterSet(charactersIn: "0123456789abcdef")
        guard normalized.count == 40,
              normalized.unicodeScalars.allSatisfy({ hexCharacters.contains($0) }) else {
            return nil
        }
        return normalized
    }

    public static func sha256Hex(for url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
            guard !data.isEmpty else { break }
            hasher.update(data: data)
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    public static func bundledManifestPublicKeyPEM() -> String {
        if let url = Bundle.main.url(forResource: manifestPublicKeyResourceName, withExtension: "pem"),
           let text = try? String(contentsOf: url, encoding: .utf8),
           text.contains("BEGIN PUBLIC KEY") {
            return text
        }
        return embeddedManifestPublicKeyPEM
    }
    public static func releaseTag(from url: URL?) -> String? {
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

    public static func versionedReleaseTag(_ tagName: String) -> String {
        "v\(normalizedVersion(tagName))"
    }
    public static func designatedRequirementLine(from codesignOutput: String) -> String? {
        codesignOutput
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.hasPrefix("designated =>") }
            .map { String($0.dropFirst("designated =>".count)).trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    public static func runTool(_ executable: String, arguments: [String]) throws {
        _ = try runToolOutput(executable, arguments: arguments)
    }

    @discardableResult
    public static func runToolOutput(_ executable: String, arguments: [String]) throws -> String {
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

    public static func latestInstallLogURL() -> URL? {
        latestInstallLogStatus().url
    }

    public static func recordLatestInstallLogURL(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: latestInstallLogKey)
    }

    public static func latestInstallLogURL(storedPath: String?,
                                    fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
                                    trustedTemporaryDirectory: URL = FileManager.default.temporaryDirectory) -> URL? {
        latestInstallLogStatus(storedPath: storedPath,
                               fileExists: fileExists,
                               trustedTemporaryDirectory: trustedTemporaryDirectory).url
    }

    public static func latestInstallLogStatus() -> InstallLogStatus {
        latestInstallLogStatus(storedPath: UserDefaults.standard.string(forKey: latestInstallLogKey))
    }

    public static func latestInstallLogStatus(storedPath: String?,
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
    public static func normalizedVersion(_ version: String) -> String {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first,
              first == "v" || first == "V" else { return trimmed }
        return String(trimmed.dropFirst())
    }

    public static func displayVersion(_ version: String) -> String {
        "v\(normalizedVersion(version))"
    }

    public static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = officialVersionComponents(lhs) ?? lhs.split(separator: ".").map { Int($0) ?? 0 }
        let right = officialVersionComponents(rhs) ?? rhs.split(separator: ".").map { Int($0) ?? 0 }
        return compareVersionComponents(left, right)
    }

    public static func compareOfficialVersions(_ lhs: String, _ rhs: String) throws -> ComparisonResult {
        guard let left = officialVersionComponents(lhs) else {
            throw UpdateError.invalidReleaseMetadata("版本号格式无效: \(lhs)。")
        }
        guard let right = officialVersionComponents(rhs) else {
            throw UpdateError.invalidReleaseMetadata("当前版本号格式无效: \(rhs)。")
        }
        return compareVersionComponents(left, right)
    }

    public static func officialVersionComponents(_ version: String) -> [Int]? {
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
