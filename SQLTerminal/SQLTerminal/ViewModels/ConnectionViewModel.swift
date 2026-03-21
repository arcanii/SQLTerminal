
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
        defaults.set(connection.username,         forKey: Keys.username)
        // Never save password — user re-enters it each time
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
    }
}
