//
//  Keychain.swift
//  Dear Diary
//
//  Stores one secret (the Claude API key) in the macOS Keychain.
//  The key is never written to a file, to UserDefaults, or to a log.
//

import Foundation
import Security

struct Keychain {
    /// Groups the item in the Keychain. Tests use their own service name so they
    /// can never see or change the real key.
    let service: String
    let account: String

    /// Where the app keeps the Claude API key.
    static let apiKey = Keychain(
        service: (Bundle.main.bundleIdentifier ?? "com.priyanshuratnakar.deardiary") + ".anthropic-api-key",
        account: "api-key"
    )

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// Returns the stored secret, or nil if there isn't one.
    func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    /// Saves the secret, replacing any earlier one. Returns false if the Keychain refused.
    @discardableResult
    func save(_ value: String) -> Bool {
        let data = Data(value.utf8)

        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return true
        }
        guard updateStatus == errSecItemNotFound else {
            return false
        }

        var newItem = baseQuery
        newItem[kSecValueData as String] = data
        newItem[kSecAttrLabel as String] = "Dear Diary API key"
        return SecItemAdd(newItem as CFDictionary, nil) == errSecSuccess
    }

    /// Removes the secret. Returns true if it is gone afterwards.
    @discardableResult
    func delete() -> Bool {
        let status = SecItemDelete(baseQuery as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
