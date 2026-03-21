// PostgresProvider.swift
// SQLTerminal
//
// MARK: - 🚧 STUB — Implement when you add PostgreSQL support.
//
// Recommended libraries:
//   • PostgresNIO  (Vapor ecosystem, async/await)
//   • PostgresClientKit (simpler, synchronous)
//
// Conform to `DatabaseProvider` and you're done — the rest of the app
// picks it up automatically through the `DatabaseProviderFactory`.

import Foundation

final class PostgresProvider: DatabaseProvider {

    let engine: DatabaseEngine = .postgres
    private(set) var isConnected = false
    private(set) var statusMessage = "PostgreSQL — not yet implemented"

    func connect(with connection: DatabaseConnection) throws {
        throw PostgresError.notImplemented
    }

    func disconnect() {
        isConnected = false
    }

    func execute(sql: String) -> QueryResult {
        .failure("PostgreSQL provider is not yet implemented.")
    }
}

enum PostgresError: LocalizedError {
    case notImplemented

    var errorDescription: String? {
        "PostgreSQL support is coming soon."
    }
}

