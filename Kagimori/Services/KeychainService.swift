import Foundation
import Security

enum KeychainService {
    private static let service = "com.kagimori.otp"

    static func save(secret: String, for key: String) -> Bool {
        guard let data = secret.data(using: .utf8) else { return false }

        // Try to add a new synchronizable item. Never delete first.
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
            kSecAttrSynchronizable as String: true,
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecSuccess { return true }
        guard addStatus == errSecDuplicateItem else { return false }

        // A synchronizable item already exists — update its value in place.
        let matchQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: true,
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        return SecItemUpdate(matchQuery as CFDictionary, attributes as CFDictionary) == errSecSuccess
    }

    static func retrieve(for key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func delete(for key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Diagnostics (temporary)

    /// Probes the keychain for `key` across synchronizability scopes and reports
    /// what the app's read path actually sees. Never returns the secret itself.
    static func diagnose(for key: String) -> KeychainDiagnosis {
        let local = existsStatus(for: key, synchronizable: false) == errSecSuccess
        let syncable = existsStatus(for: key, synchronizable: true) == errSecSuccess
        let presence: KeychainDiagnosis.Presence =
            switch (local, syncable) {
            case (true, true): .both
            case (true, false): .localOnly
            case (false, true): .syncableOnly
            case (false, false): .absent
            }

        // Mirror the exact query `retrieve` uses, but capture the status.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        var secretLength: Int?
        var decodes = false
        var decodedByteCount: Int?
        if status == errSecSuccess,
           let data = result as? Data,
           let secret = String(data: data, encoding: .utf8) {
            secretLength = secret.count
            if let decoded = Base32.decode(secret) {
                decodes = true
                decodedByteCount = decoded.count
            }
        }

        return KeychainDiagnosis(
            presence: presence,
            readStatus: status,
            secretLength: secretLength,
            decodes: decodes,
            decodedByteCount: decodedByteCount
        )
    }

    private static func existsStatus(for key: String, synchronizable: Bool) -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrSynchronizable as String: synchronizable,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil)
    }
}

// MARK: - Diagnostics model (temporary)

struct KeychainDiagnosis: Sendable {
    enum Presence: String, Sendable {
        case absent = "absent"
        case localOnly = "local only"
        case syncableOnly = "iCloud only"
        case both = "local + iCloud"
    }

    let presence: Presence
    let readStatus: OSStatus
    let secretLength: Int?
    let decodes: Bool
    let decodedByteCount: Int?

    var readStatusMessage: String {
        if readStatus == errSecSuccess { return "ok" }
        let message = SecCopyErrorMessageString(readStatus, nil) as String?
        return "\(readStatus) \(message ?? "")"
    }
}
