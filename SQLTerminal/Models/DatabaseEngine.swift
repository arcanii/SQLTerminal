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

