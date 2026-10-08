import Foundation
import Security

/// Passwords, which the app keeps in the keychain rather than with its other
/// settings.
nonisolated enum Keychain {
    private static let service = "com.camerac64"

    /// The password saved under a name, or an empty string for none.
    static func password(_ name: String) -> String {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: name,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return ""
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// Saves a password under a name, or removes it if it is empty.
    static func setPassword(_ password: String, for name: String) {
        let item: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: name,
        ]
        SecItemDelete(item as CFDictionary)
        guard !password.isEmpty else { return }
        var added = item
        added[kSecValueData] = Data(password.utf8)
        added[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(added as CFDictionary, nil)
    }
}
