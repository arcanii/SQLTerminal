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
// ConnectionViewModel.swift
// SQLTerminal

import SwiftUI
import Combine
import AppKit
import UniformTypeIdentifiers

@MainActor
final class ConnectionViewModel: ObservableObject {
    @Published var connection = DatabaseConnection()
    @Published var errorMessage: String?
    @Published var securityScopedURL: URL?
    /// Whether to persist this connection's password in the Keychain.
    @Published var savePassword = false

    // MARK: - UserDefaults keys

    private enum Keys {
        static let engine       = "lastEngine"
        static let filePath     = "lastFilePath"
        static let host         = "lastHost"
        static let port         = "lastPort"
        static let databaseName = "lastDatabaseName"
        static let username     = "lastUsername"
    }

    // MARK: - Init: load saved connection

    init() {
        loadLastConnection()
    }

    // MARK: - Computed

    var canConnect: Bool {
        switch connection.engine {
        case .sqlite:
            return !connection.filePath.trimmingCharacters(in: .whitespaces).isEmpty
        case .postgres:
            return !connection.host.isEmpty
                && !connection.port.isEmpty
                && !connection.databaseName.isEmpty
                && !connection.username.isEmpty
        }
    }

    // MARK: - File browsing

    func browseForFile() {
        let openPanel = NSOpenPanel()
        openPanel.title = "Select SQLite Database"
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false
        openPanel.allowedContentTypes = [.data, .item]

        if openPanel.runModal() == .OK, let url = openPanel.url {
            connection.filePath = url.path
            securityScopedURL = url
        }
    }

    func browseForNewFile() {
        let savePanel = NSSavePanel()
        savePanel.title = "Create New SQLite Database"
        savePanel.nameFieldStringValue = "database.sqlite"
        savePanel.allowedContentTypes = [.data]

        if savePanel.runModal() == .OK, let url = savePanel.url {
            connection.filePath = url.path
            securityScopedURL = url
        }
    }

    // MARK: - Save / Load

    func saveLastConnection() {
        let defaults = UserDefaults.standard
        defaults.set(connection.engine.rawValue, forKey: Keys.engine)
        defaults.set(connection.filePath,        forKey: Keys.filePath)
        defaults.set(connection.host,            forKey: Keys.host)
        defaults.set(connection.port,            forKey: Keys.port)
        defaults.set(connection.databaseName,    forKey: Keys.databaseName)
        defaults.set(connection.username,        forKey: Keys.username)
        // The password is kept in the Keychain (when opted in), never UserDefaults.
        updateStoredPassword()
    }

    /// Persist just the engine choice immediately. `saveLastConnection()` only
    /// runs after a *successful* connect, so without this a failed PostgreSQL
    /// attempt would leave the sheet reopening on SQLite. Calling this on every
    /// engine change makes the sheet reopen to whatever engine you last picked.
    func rememberEngine() {
        UserDefaults.standard.set(connection.engine.rawValue, forKey: Keys.engine)
    }

    /// Save or remove this connection's password in the Keychain based on the
    /// `savePassword` toggle. PostgreSQL only — SQLite has no password.
    private func updateStoredPassword() {
        guard connection.engine == .postgres, !connection.username.isEmpty else { return }
        let key = KeychainHelper.account(for: connection)
        if savePassword, !connection.password.isEmpty {
            KeychainHelper.savePassword(connection.password, account: key)
        } else {
            KeychainHelper.deletePassword(account: key)
        }
    }

    private func loadLastConnection() {
        let defaults = UserDefaults.standard

        if let engineRaw = defaults.string(forKey: Keys.engine),
           let engine = DatabaseEngine(rawValue: engineRaw) {
            connection.engine = engine
        }

        if let filePath = defaults.string(forKey: Keys.filePath), !filePath.isEmpty {
            connection.filePath = filePath
        }

        if let host = defaults.string(forKey: Keys.host), !host.isEmpty {
            connection.host = host
        }

        if let port = defaults.string(forKey: Keys.port), !port.isEmpty {
            connection.port = port
        }

        if let dbName = defaults.string(forKey: Keys.databaseName), !dbName.isEmpty {
            connection.databaseName = dbName
        }

        if let username = defaults.string(forKey: Keys.username), !username.isEmpty {
            connection.username = username
        }

        // Restore a saved password from the Keychain (PostgreSQL only). The login
        // keychain is already unlocked, so this needs no extra prompt.
        if connection.engine == .postgres,
           !connection.username.isEmpty, !connection.host.isEmpty,
           let stored = KeychainHelper.password(account: KeychainHelper.account(for: connection)) {
            connection.password = stored
            savePassword = true
        }
    }
}
