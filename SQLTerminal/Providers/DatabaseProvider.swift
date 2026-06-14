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
///
/// The protocol is `nonisolated` (the project defaults declarations to
/// `@MainActor`) because providers are driven entirely from a `DatabaseSession`'s
/// background serial queue — never the main actor. See `DatabaseSession`.
nonisolated protocol DatabaseProvider: AnyObject {

    /// Which engine this provider represents.
    var engine: DatabaseEngine { get }

    /// Whether the provider currently has an open connection.
    var isConnected: Bool { get }

    /// Whether the live connection is actually encrypted (SSL/TLS). Reflects what
    /// was *negotiated*, not the requested mode — a Postgres `.prefer` connection
    /// that fell back to plaintext reports `false`. Always `false` for SQLite.
    var isSSLActive: Bool { get }

    /// Human-readable status, e.g. "Connected to mydb.sqlite".
    var statusMessage: String { get }

    /// Open a connection using the given configuration.
    func connect(with connection: DatabaseConnection) throws

    /// Close the current connection and release resources.
    func disconnect()

    /// Execute arbitrary SQL and return a unified `QueryResult`.
    func execute(sql: String) -> QueryResult

    /// Interrupt the query currently running in `execute(sql:)`.
    ///
    /// **Must be safe to call from a different thread than the one executing**,
    /// since cancellation arrives while `execute(sql:)` is blocked on I/O. The
    /// in-flight call is expected to unblock and return (typically an error).
    /// Implementations may leave the connection unusable afterwards (Postgres
    /// closes the socket); callers should reconnect if `isConnected` allows.
    func cancel()
}

