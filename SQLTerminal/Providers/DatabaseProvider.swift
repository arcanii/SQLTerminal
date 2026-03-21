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
// DatabaseProvider.swift
// SQLTerminal

import Foundation

/// **The single protocol every database engine must implement.**
///
/// To add PostgreSQL support later, create a class that conforms to
/// `DatabaseProvider` and you're done — the UI doesn't change at all.
protocol DatabaseProvider: AnyObject {

    /// Which engine this provider represents.
    var engine: DatabaseEngine { get }

    /// Whether the provider currently has an open connection.
    var isConnected: Bool { get }

    /// Human-readable status, e.g. "Connected to mydb.sqlite".
    var statusMessage: String { get }

    /// Open a connection using the given configuration.
    func connect(with connection: DatabaseConnection) throws

    /// Close the current connection and release resources.
    func disconnect()

    /// Execute arbitrary SQL and return a unified `QueryResult`.
    func execute(sql: String) -> QueryResult
}

