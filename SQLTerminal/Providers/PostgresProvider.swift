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
// PostgresProvider.swift
// SQLTerminal

import Foundation
import PostgresClientKit

final class PostgresProvider: DatabaseProvider {

    let engine: DatabaseEngine = .postgres
    private(set) var isConnected = false
    private(set) var statusMessage = "Disconnected"

    private var connection: Connection?

    deinit { disconnect() }

    // MARK: - Connect

    func connect(with config: DatabaseConnection) throws {
        disconnect()

        // Enable logging for troubleshooting
        Postgres.logger.level = .warning

        var pgConfig = PostgresClientKit.ConnectionConfiguration()
        pgConfig.host = config.host
        pgConfig.port = Int(config.port) ?? 5432
        pgConfig.database = config.databaseName
        pgConfig.user = config.username
        pgConfig.ssl = false

        // Try authentication methods in order of likelihood
        let authMethods: [(String, Credential)] = [
            ("SCRAM-SHA-256", .scramSHA256(password: config.password)),
            ("MD5",           .md5Password(password: config.password)),
            ("Plain",         .cleartextPassword(password: config.password)),
            ("Trust",         .trust),
        ]

        var lastError: Error?

        for (name, credential) in authMethods {
            pgConfig.credential = credential
            do {
                connection = try PostgresClientKit.Connection(configuration: pgConfig)
                isConnected = true
                statusMessage = "Connected to \(config.username)@\(config.host):\(config.port)/\(config.databaseName) [\(name)]"
                return
            } catch {
                lastError = error
                connection = nil
                // Continue trying next method
            }
        }

        // All methods failed
        disconnect()
        throw PostgresError.connectionFailed(
            lastError?.localizedDescription ?? "All authentication methods failed"
        )
    }

    // MARK: - Disconnect

    func disconnect() {
        connection?.close()
        connection = nil
        isConnected = false
        statusMessage = "Disconnected"
    }

    // MARK: - Execute

    func execute(sql: String) -> QueryResult {
        guard let connection = connection else {
            return .failure("No database connection.")
        }

        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure("Empty query.")
        }

        let start = CFAbsoluteTimeGetCurrent()

        do {
            let statement = try connection.prepareStatement(text: trimmed)
            defer { statement.close() }

            // retrieveColumnMetadata MUST be true to get column names
            let cursor = try statement.execute(retrieveColumnMetadata: true)
            defer { cursor.close() }

            // Get column names
            let columnNames: [String]
            if let columns = cursor.columns {
                columnNames = columns.map { $0.name }
            } else {
                columnNames = []
            }

            // Fetch rows
            var rows: [[String]] = []
            for row in cursor {
                let columns = try row.get().columns
                var rowValues: [String] = []
                for col in columns {
                    if col.isNull {
                        rowValues.append("NULL")
                    } else {
                        do {
                            let value = try col.string()
                            rowValues.append(value)
                        } catch {
                            rowValues.append(col.postgresValue.rawValue ?? "NULL")
                        }
                    }
                }
                rows.append(rowValues)
            }

            let elapsed = CFAbsoluteTimeGetCurrent() - start

            // Determine statement type
            let isQuery = !columnNames.isEmpty
            let upperSQL = trimmed.uppercased().trimmingCharacters(in: .whitespaces)
            let isMutation = upperSQL.hasPrefix("INSERT") ||
                             upperSQL.hasPrefix("UPDATE") ||
                             upperSQL.hasPrefix("DELETE") ||
                             upperSQL.hasPrefix("CREATE") ||
                             upperSQL.hasPrefix("DROP") ||
                             upperSQL.hasPrefix("ALTER") ||
                             upperSQL.hasPrefix("TRUNCATE")

            if isQuery {
                return QueryResult(
                    columns: columnNames,
                    rows: rows,
                    rowsAffected: rows.count,
                    executionTime: elapsed,
                    error: nil,
                    statementType: .query
                )
            } else {
                return QueryResult(
                    columns: [],
                    rows: [],
                    rowsAffected: 0,
                    executionTime: elapsed,
                    error: nil,
                    statementType: .mutation
                )
            }

        } catch {
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            return QueryResult(
                columns: [],
                rows: [],
                rowsAffected: 0,
                executionTime: elapsed,
                error: error.localizedDescription,
                statementType: .error
            )
        }
    }

}

enum PostgresError: LocalizedError {
    case connectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let msg):
            return "PostgreSQL connection failed: \(msg)"
        }
    }
}
