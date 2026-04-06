import Foundation
import Security

enum GitCredentialStore {
    private static let service = "RepoMonitor.git-host-token"

    enum StoreError: LocalizedError {
        case emptyValue(String)
        case unexpectedStatus(OSStatus)

        var errorDescription: String? {
            switch self {
            case .emptyValue(let field):
                return "\(field) cannot be empty."
            case .unexpectedStatus(let status):
                if let message = SecCopyErrorMessageString(status, nil) as String? {
                    return message
                }
                return "Keychain error \(status)."
            }
        }
    }

    static func saveToken(_ token: String, host: String, username: String) throws {
        let normalizedHost = GitHostCredential.normalizeHost(host)
        let normalizedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedHost.isEmpty else { throw StoreError.emptyValue("Host") }
        guard !normalizedUsername.isEmpty else { throw StoreError.emptyValue("Username") }
        guard !normalizedToken.isEmpty else { throw StoreError.emptyValue("Token") }

        let query = keychainQuery(host: normalizedHost, username: normalizedUsername)
        let data = Data(normalizedToken.utf8)

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            guard updateStatus == errSecSuccess else { throw StoreError.unexpectedStatus(updateStatus) }
        case errSecItemNotFound:
            var attributes = query
            attributes[kSecValueData as String] = data
            attributes[kSecAttrLabel as String] = "\(normalizedHost) (\(normalizedUsername))"
            let addStatus = SecItemAdd(attributes as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw StoreError.unexpectedStatus(addStatus) }
        default:
            throw StoreError.unexpectedStatus(status)
        }
    }

    static func token(host: String, username: String) -> String? {
        var query = keychainQuery(host: host, username: username)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }
        return token
    }

    static func hasToken(host: String, username: String) -> Bool {
        token(host: host, username: username) != nil
    }

    static func deleteToken(host: String, username: String) {
        let query = keychainQuery(host: host, username: username)
        SecItemDelete(query as CFDictionary)
    }

    private static func keychainQuery(host: String, username: String) -> [String: Any] {
        let normalizedHost = GitHostCredential.normalizeHost(host)
        let normalizedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)

        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "\(normalizedHost)|\(normalizedUsername)"
        ]
    }
}
