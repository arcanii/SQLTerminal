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
