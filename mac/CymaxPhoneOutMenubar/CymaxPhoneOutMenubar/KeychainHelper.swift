//
//  KeychainHelper.swift
//  CymaxPhoneOutMenubar
//
//  Securely stores and retrieves login credentials using macOS Keychain.
//

import Foundation
import Security

struct KeychainHelper {

    private static let service = "com.cymatics.mixlink.subscription"
    private static let emailKey = "cymatics_email"
    private static let passwordKey = "cymatics_password"

    // MARK: - Save

    static func saveCredentials(email: String, password: String) {
        save(key: emailKey, value: email)
        save(key: passwordKey, value: password)
    }

    // MARK: - Load

    static func loadCredentials() -> (email: String, password: String)? {
        guard let email = load(key: emailKey),
              let password = load(key: passwordKey) else {
            return nil
        }
        return (email, password)
    }

    // MARK: - Delete

    static func clearCredentials() {
        delete(key: emailKey)
        delete(key: passwordKey)
    }

    // MARK: - Has Saved

    static var hasSavedCredentials: Bool {
        return load(key: emailKey) != nil && load(key: passwordKey) != nil
    }

    // MARK: - Private Keychain Operations

    private static func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }

        // Delete any existing item first
        delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]

        SecItemAdd(query as CFDictionary, nil)
    }

    private static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }

        return string
    }

    private static func delete(key: String) {
        // Delete from legacy keychain (cleans up old items from previous versions)
        let legacyQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(legacyQuery as CFDictionary)

        // Delete from Data Protection keychain
        let dpQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecUseDataProtectionKeychain as String: true
        ]
        SecItemDelete(dpQuery as CFDictionary)
    }
}
