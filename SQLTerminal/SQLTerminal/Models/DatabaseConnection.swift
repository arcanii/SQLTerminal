// DatabaseConnection.swift
// SQLTerminal

import Foundation

struct DatabaseConnection {
    var engine: DatabaseEngine = .sqlite
    var filePath: String = ""
    var host: String = "localhost"
    var port: String = "5432"
    var databaseName: String = ""
    var username: String = ""
    var password: String = ""

    /// Security-scoped URL from NSOpenPanel/NSSavePanel (sandbox support)
    var securityScopedURL: URL?

    var displayName: String {
        switch engine {
        case .sqlite:
            let name = (filePath as NSString).lastPathComponent
            return name.isEmpty ? "No database" : "SQLite: \(name)"
        case .postgres:
            return "PostgreSQL: \(username)@\(host):\(port)/\(databaseName)"
        }
    }
}
