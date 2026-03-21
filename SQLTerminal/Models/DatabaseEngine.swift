// DatabaseEngine.swift
// SQLTerminal

import Foundation

/// Every database backend the app can support.
/// Add new cases here when you add a provider.
enum DatabaseEngine: String, CaseIterable, Identifiable, Codable {
    case sqlite   = "SQLite"
    case postgres = "PostgreSQL"    // future

    var id: String { rawValue }

    /// Which connection fields are relevant for this engine.
    var requiresHost: Bool {
        switch self {
        case .sqlite:   return false
        case .postgres: return true
        }
    }

    var requiresPort: Bool {
        switch self {
        case .sqlite:   return false
        case .postgres: return true
        }
    }

    var requiresCredentials: Bool {
        switch self {
        case .sqlite:   return false
        case .postgres: return true
        }
    }

    var defaultPort: String {
        switch self {
        case .sqlite:   return ""
        case .postgres: return "5432"
        }
    }

    var filePlaceholder: String {
        switch self {
        case .sqlite:   return "/path/to/database.db"
        case .postgres: return ""
        }
    }
}

