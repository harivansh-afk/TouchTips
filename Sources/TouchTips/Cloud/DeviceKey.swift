// The phone's cloud credential: random bytes made once, kept in the Keychain, never synced.
// The server only ever sees its hash. Losing it means a fresh cloud identity, by design.

import Foundation
import Security

enum DeviceKey {
    private static let service = "sh.harivan.touchtips.cloud"
    private static let account = "device-key"

    static func existing() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let key = String(data: data, encoding: .utf8) else { return nil }
        return key
    }

    static func getOrCreate() throws -> String {
        if let key = existing() {
            return key
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw CloudError.keychain(errSecInternalError)
        }
        let key = "tt_" + Data(bytes).base64URLEncoded
        var add = baseQuery
        add[kSecValueData as String] = Data(key.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw CloudError.keychain(status) }
        return key
    }

    static func forget() {
        _ = SecItemDelete(baseQuery as CFDictionary)
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
