import CryptoKit
import Foundation

/// 本地加密密钥存储。API Key 不进入 UserDefaults、导出配置或 iCloud payload。
///
/// 安全边界:master key 与密文都保存在当前用户的 Application Support 目录,
/// 并通过 AES.GCM + 受限文件权限避免明文落盘。它不会触发 macOS Keychain 授权,
/// 但也不等同于 Keychain 对同一用户进程的系统级隔离。
enum LocalSecretStore {
    private static let store = Store()

    static func apiKey(for providerID: String) -> String {
        store.apiKey(for: providerID)
    }

    @discardableResult
    static func setAPIKey(_ key: String, for providerID: String) -> Bool {
        store.setAPIKey(key, for: providerID)
    }

    @discardableResult
    static func delete(providerID: String) -> Bool {
        store.delete(providerID: providerID)
    }

    static func diagnosticSummary() -> String {
        store.diagnosticSummary()
    }

    struct Store {
        private let directoryURL: URL
        private let fileManager: FileManager

        init(directoryURL: URL = Store.defaultDirectoryURL(),
             fileManager: FileManager = .default) {
            self.directoryURL = directoryURL
            self.fileManager = fileManager
        }

        func apiKey(for providerID: String) -> String {
            guard let providerKey = normalizedProviderID(providerID),
                  let masterKey = try? loadMasterKey(createIfMissing: false),
                  let envelope = try? loadEnvelope(),
                  let record = envelope.providers[providerKey],
                  let value = try? decrypt(record, using: masterKey) else {
                return ""
            }
            return value
        }

        @discardableResult
        func setAPIKey(_ key: String, for providerID: String) -> Bool {
            guard let providerKey = normalizedProviderID(providerID) else { return false }
            let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedKey.isEmpty {
                return delete(providerID: providerKey)
            }

            do {
                let masterKey = try loadMasterKey(createIfMissing: true)
                var envelope = try loadEnvelope()
                envelope.providers[providerKey] = try encrypt(key, using: masterKey)
                try writeEnvelope(envelope)
                return true
            } catch {
                return false
            }
        }

        @discardableResult
        func delete(providerID: String) -> Bool {
            guard let providerKey = normalizedProviderID(providerID) else { return false }
            do {
                var envelope = try loadEnvelope()
                envelope.providers.removeValue(forKey: providerKey)
                try writeEnvelope(envelope)
                return true
            } catch {
                return false
            }
        }

        func diagnosticSummary() -> String {
            var parts: [String] = []
            parts.append("mode=local-encrypted")
            parts.append("directory=\(fileManager.fileExists(atPath: directoryURL.path) ? "present" : "missing")")
            parts.append("key=\(fileManager.fileExists(atPath: keyURL.path) ? "present" : "missing")")
            parts.append("store=\(fileManager.fileExists(atPath: secretsURL.path) ? "present" : "missing")")
            if let directoryMode = permissions(at: directoryURL) {
                parts.append("directoryMode=\(directoryMode)")
            }
            if let keyMode = permissions(at: keyURL) {
                parts.append("keyMode=\(keyMode)")
            }
            if let storeMode = permissions(at: secretsURL) {
                parts.append("storeMode=\(storeMode)")
            }
            return parts.joined(separator: ", ")
        }

        private var keyURL: URL {
            directoryURL.appendingPathComponent("snapai-secrets.key", isDirectory: false)
        }

        private var secretsURL: URL {
            directoryURL.appendingPathComponent("provider-secrets.json", isDirectory: false)
        }

        private static func defaultDirectoryURL() -> URL {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
            return base
                .appendingPathComponent("SnapAI", isDirectory: true)
                .appendingPathComponent("Secrets", isDirectory: true)
        }

        private func normalizedProviderID(_ providerID: String) -> String? {
            let trimmed = providerID.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        private func ensureDirectory() throws {
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory) {
                guard isDirectory.boolValue else { throw StoreError.directoryPathIsFile }
            } else {
                try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            }
            try setPermissions(0o700, at: directoryURL)
        }

        private func loadMasterKey(createIfMissing: Bool) throws -> SymmetricKey {
            if fileManager.fileExists(atPath: keyURL.path) {
                let encoded = try Data(contentsOf: keyURL)
                let trimmed = String(data: encoded, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard let raw = Data(base64Encoded: trimmed), raw.count == 32 else {
                    throw StoreError.invalidMasterKey
                }
                try setPermissions(0o600, at: keyURL)
                return SymmetricKey(data: raw)
            }

            guard createIfMissing else { throw StoreError.missingMasterKey }
            try ensureDirectory()
            let key = SymmetricKey(size: .bits256)
            let raw = key.withUnsafeBytes { Data($0) }
            try writeRestricted(raw.base64EncodedData(), to: keyURL)
            return key
        }

        private func loadEnvelope() throws -> SecretsEnvelope {
            guard fileManager.fileExists(atPath: secretsURL.path) else {
                return SecretsEnvelope()
            }
            let data = try Data(contentsOf: secretsURL)
            try setPermissions(0o600, at: secretsURL)
            return try JSONDecoder().decode(SecretsEnvelope.self, from: data)
        }

        private func writeEnvelope(_ envelope: SecretsEnvelope) throws {
            try ensureDirectory()
            if envelope.providers.isEmpty {
                if fileManager.fileExists(atPath: secretsURL.path) {
                    try fileManager.removeItem(at: secretsURL)
                }
                return
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(envelope)
            try writeRestricted(data, to: secretsURL)
        }

        private func encrypt(_ value: String, using key: SymmetricKey) throws -> SecretRecord {
            let sealedBox = try AES.GCM.seal(Data(value.utf8), using: key)
            let nonceData = sealedBox.nonce.withUnsafeBytes { Data($0) }
            return SecretRecord(nonce: nonceData.base64EncodedString(),
                                ciphertext: sealedBox.ciphertext.base64EncodedString(),
                                tag: sealedBox.tag.base64EncodedString())
        }

        private func decrypt(_ record: SecretRecord, using key: SymmetricKey) throws -> String {
            guard let nonceData = Data(base64Encoded: record.nonce),
                  let ciphertext = Data(base64Encoded: record.ciphertext),
                  let tag = Data(base64Encoded: record.tag) else {
                throw StoreError.invalidCiphertext
            }
            let nonce = try AES.GCM.Nonce(data: nonceData)
            let sealedBox = try AES.GCM.SealedBox(nonce: nonce,
                                                  ciphertext: ciphertext,
                                                  tag: tag)
            let opened = try AES.GCM.open(sealedBox, using: key)
            guard let string = String(data: opened, encoding: .utf8) else {
                throw StoreError.invalidPlaintext
            }
            return string
        }

        private func writeRestricted(_ data: Data, to url: URL) throws {
            try ensureDirectory()
            let temporaryURL = directoryURL.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
            try data.write(to: temporaryURL, options: [])
            try setPermissions(0o600, at: temporaryURL)
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
            try fileManager.moveItem(at: temporaryURL, to: url)
            try setPermissions(0o600, at: url)
        }

        private func setPermissions(_ permissions: Int, at url: URL) throws {
            guard fileManager.fileExists(atPath: url.path) else { return }
            try fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
        }

        private func permissions(at url: URL) -> String? {
            guard let attrs = try? fileManager.attributesOfItem(atPath: url.path),
                  let value = attrs[.posixPermissions] as? NSNumber else {
                return nil
            }
            return String(format: "%03o", value.intValue & 0o777)
        }
    }
}

private struct SecretsEnvelope: Codable {
    var schemaVersion: Int = 1
    var providers: [String: SecretRecord] = [:]
}

private struct SecretRecord: Codable {
    var nonce: String
    var ciphertext: String
    var tag: String
}

private enum StoreError: Error {
    case directoryPathIsFile
    case missingMasterKey
    case invalidMasterKey
    case invalidCiphertext
    case invalidPlaintext
}
