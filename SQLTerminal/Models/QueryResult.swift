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
// QueryResult.swift
// SQLTerminal

import Foundation

/// A unified result type every provider returns after executing SQL.
struct QueryResult: Identifiable {
    let id = UUID()
    let columns: [String]
    let rows: [[String]]
    let rowsAffected: Int
    let executionTime: TimeInterval
    let error: String?
    let statementType: StatementType

    enum StatementType {
        case query      // SELECT, PRAGMA, etc. – returns rows
        case mutation   // INSERT, UPDATE, DELETE, CREATE, DROP, etc.
        case error
    }

    /// Convenience: a result that carries only an error.
    static func failure(_ message: String) -> QueryResult {
        QueryResult(
            columns: [],
            rows: [],
            rowsAffected: 0,
            executionTime: 0,
            error: message,
            statementType: .error
        )
    }
}

