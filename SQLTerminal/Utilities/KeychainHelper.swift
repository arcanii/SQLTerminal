/*
 SQLTerminal - a simple dev tool to connect to {sqlite3, postgres} and run sql commands
     Copyright (C) 2026 bryan.mark@gmail.com

     This program is free software: you can redistribute it and/or modify
     it under the terms of the GNU General Public License as published by
     the Free Software Foundation, either version 3 of the License, or
     (at your option) any later version.

     This program is distributed in the hope that it will be useful,
     but WITHOUT ANY WARRANTY; without even the implied warranty of
     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
     GNU General Public License for more details.

     You should have received a copy of the GNU General Public License
     along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */
// KeychainHelper.swift
// SQLTerminal
//
// Stores connection passwords in the macOS login Keychain. Items are accessible
// once the keychain is unlocked at login, so a saved password is restored on the
// next launch without re-typing. Used only for PostgreSQL (SQLite has no
// password). Items the app creates are readable by it without an extra prompt.

import Foundation
import Security

enum KeychainHelper {
    private static let service = "SQLTerminal"

    /// A stable, unique key for a connection's password.
    static func account(for connection: DatabaseConnection) -> String {
        "\(connection.username)@\(connection.host):\(connection.port)/\(connection.databaseName)"
    }

    @discardableResult
    static func savePassword(_ password: String, account: String) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        // Replace any existing value for this account.
        SecItemDelete(base as CFDictionary)

        guard let data = password.data(using: .utf8) else { return false }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func password(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func deletePassword(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
