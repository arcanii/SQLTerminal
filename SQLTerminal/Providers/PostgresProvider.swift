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

        // Split into individual statements, respecting $$ blocks
        let statements = splitStatements(trimmed)

        let start = CFAbsoluteTimeGetCurrent()

        var lastColumns: [String] = []
        var lastRows: [[String]] = []
        var totalRowsAffected = 0
        var lastWasQuery = false

        for sql in statements {
            let stmt = sql.trimmingCharacters(in: .whitespacesAndNewlines)
            if stmt.isEmpty { continue }

            // Skip psql meta-commands
            if stmt.hasPrefix("\\") {
                continue
            }

            // Skip lines that are only comments
            let uncommented = stmt.components(separatedBy: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("--") }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if uncommented.isEmpty { continue }

            let result = executeSingle(connection: connection, sql: stmt)

            if let error = result.error {
                let elapsed = CFAbsoluteTimeGetCurrent() - start
                return QueryResult(
                    columns: result.columns,
                    rows: result.rows,
                    rowsAffected: totalRowsAffected,
                    executionTime: elapsed,
                    error: error,
                    statementType: .error
                )
            }

            if !result.columns.isEmpty {
                lastColumns = result.columns
                lastRows = result.rows
                lastWasQuery = true
            } else {
                lastWasQuery = false
            }
            totalRowsAffected += result.rowsAffected
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - start

        return QueryResult(
            columns: lastColumns,
            rows: lastRows,
            rowsAffected: totalRowsAffected,
            executionTime: elapsed,
            error: nil,
            statementType: lastWasQuery ? .query : .mutation
        )
    }

    // MARK: - Execute single statement

    private func executeSingle(connection: Connection, sql: String) -> QueryResult {
        do {
            let statement = try connection.prepareStatement(text: sql)
            defer { statement.close() }

            let cursor = try statement.execute(retrieveColumnMetadata: true)
            defer { cursor.close() }

            let columnNames: [String]
            if let columns = cursor.columns {
                columnNames = columns.map { $0.name }
            } else {
                columnNames = []
            }

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

            return QueryResult(
                columns: columnNames,
                rows: rows,
                rowsAffected: rows.count,
                executionTime: 0,
                error: nil,
                statementType: columnNames.isEmpty ? .mutation : .query
            )

        } catch {
            return QueryResult(
                columns: [],
                rows: [],
                rowsAffected: 0,
                executionTime: 0,
                error: error.localizedDescription,
                statementType: .error
            )
        }
    }

    // MARK: - Statement splitter (respects $$ dollar-quoted blocks)

    private func splitStatements(_ sql: String) -> [String] {
        var statements: [String] = []
        var current = ""
        var inDollarQuote = false
        var dollarTag = ""
        var inSingleQuote = false
        var inLineComment = false
        var inBlockComment = false
        let chars = Array(sql)
        var i = 0

        while i < chars.count {
            let c = chars[i]
            let next: Character? = (i + 1 < chars.count) ? chars[i + 1] : nil

            // Line comment
            if !inSingleQuote && !inDollarQuote && !inBlockComment
                && c == "-" && next == "-" {
                inLineComment = true
                current.append(c)
                i += 1
                continue
            }
            if inLineComment {
                current.append(c)
                if c == "\n" { inLineComment = false }
                i += 1
                continue
            }

            // Block comment
            if !inSingleQuote && !inDollarQuote && !inBlockComment
                && c == "/" && next == "*" {
                inBlockComment = true
                current.append(c)
                i += 1
                continue
            }
            if inBlockComment {
                current.append(c)
                if c == "*" && next == "/" {
                    current.append(next!)
                    inBlockComment = false
                    i += 2
                    continue
                }
                i += 1
                continue
            }

            // Dollar quoting: $tag$ ... $tag$
            if !inSingleQuote && c == "$" {
                // Find the tag
                var tag = "$"
                var j = i + 1
                while j < chars.count && (chars[j].isLetter || chars[j].isNumber || chars[j] == "_") {
                    tag.append(chars[j])
                    j += 1
                }
                if j < chars.count && chars[j] == "$" {
                    tag.append("$")
                    if inDollarQuote && tag == dollarTag {
                        // End of dollar quote
                        current.append(tag)
                        inDollarQuote = false
                        dollarTag = ""
                        i = j + 1
                        continue
                    } else if !inDollarQuote {
                        // Start of dollar quote
                        inDollarQuote = true
                        dollarTag = tag
                        current.append(tag)
                        i = j + 1
                        continue
                    }
                }
            }

            if inDollarQuote {
                current.append(c)
                i += 1
                continue
            }

            // Single quotes
            if c == "'" && !inDollarQuote {
                inSingleQuote = !inSingleQuote
                // Handle escaped single quotes ''
                if inSingleQuote == false && next == "'" {
                    current.append(c)
                    current.append(next!)
                    inSingleQuote = true
                    i += 2
                    continue
                }
                current.append(c)
                i += 1
                continue
            }

            if inSingleQuote {
                current.append(c)
                i += 1
                continue
            }

            // Semicolon — statement boundary
            if c == ";" {
                current.append(c)
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    statements.append(trimmed)
                }
                current = ""
                i += 1
                continue
            }

            current.append(c)
            i += 1
        }

        // Remaining
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            statements.append(trimmed)
        }

        return statements
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
