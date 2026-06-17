import Foundation
import Security

/// 极简 Keychain 封装,用于安全存储各供应商的 API Key。
/// 以 "SnapAI.providerKey.<providerID>" 为 account,存在通用密码项里。
enum Keychain {
    private static let service = "com.snapai.app.apikeys"

    private static func account(_ providerID: String) -> String {
        "SnapAI.providerKey.\(providerID)"
    }

    /// 读取某供应商的 Key,不存在返回空字符串
    static func apiKey(for providerID: String) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(providerID),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let str = String(data: data, encoding: .utf8) else {
            return ""
        }
        return str
    }

    /// 写入/更新某供应商的 Key。空字符串等价于删除。
    @discardableResult
    static func setAPIKey(_ key: String, for providerID: String) -> Bool {
        if key.isEmpty {
            return delete(providerID: providerID)
        }
        let acct = account(providerID)
        let data = Data(key.utf8)

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: acct
        ]
        // 先尝试更新
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary,
                                         [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecSuccess { return true }

        // 不存在则新增
        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        return addStatus == errSecSuccess
    }

    @discardableResult
    static func delete(providerID: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(providerID)
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
