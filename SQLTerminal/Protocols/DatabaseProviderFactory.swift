// DatabaseProviderFactory.swift
// SQLTerminal

import Foundation

/// Vends the correct provider for a given engine.
/// When you add a new engine, register it here.
enum DatabaseProviderFactory {

    static func provider(for engine: DatabaseEngine) -> DatabaseProvider {
        switch engine {
        case .sqlite:   return SQLiteProvider()
        case .postgres: return PostgresProvider()
        }
    }
}

