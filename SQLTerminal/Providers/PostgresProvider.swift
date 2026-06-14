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

nonisolated final class PostgresProvider: DatabaseProvider {

    let engine: DatabaseEngine = .postgres
    private(set) var isConnected = false
    private(set) var isSSLActive = false
    private(set) var statusMessage = "Disconnected"

    private var connection: Connection?

    deinit { disconnect() }

    // MARK: - Connect

    func connect(with config: DatabaseConnection) throws {
        disconnect()
        Postgres.logger.level = .warning

        do {
            var usedSSL = false
            switch config.sslMode {
            case .off:
                connection = try establish(config, ssl: false)
            case .require:
                connection = try establish(config, ssl: true); usedSSL = true
            case .prefer:
                do {
                    connection = try establish(config, ssl: true); usedSSL = true
                } catch let error where Self.isSSLUnavailable(error) {
                    // The server doesn't speak SSL — retry unencrypted.
                    connection = try establish(config, ssl: false)
                }
            }
            isConnected = true
            isSSLActive = usedSSL
            statusMessage = "Connected to \(config.username)@\(config.host):\(config.port)/\(config.databaseName)\(usedSSL ? " (SSL)" : "")"
        } catch {
            // Could not connect — surface a detailed, actionable message.
            disconnect()
            throw PostgresError.connectionFailed(
                Self.describeConnectionError(error,
                                             host: config.host,
                                             port: Int(config.port) ?? 5432,
                                             database: config.databaseName,
                                             user: config.username)
            )
        }
    }

    /// Open a connection with the given SSL setting, trying each credential type
    /// until one is accepted. Throws the raw PostgresClientKit error on failure so
    /// the caller can detect SSL-unavailability (for `.prefer`) before formatting.
    private func establish(_ config: DatabaseConnection, ssl: Bool) throws -> Connection {
        var pgConfig = PostgresClientKit.ConnectionConfiguration()
        pgConfig.host = config.host
        pgConfig.port = Int(config.port) ?? 5432
        pgConfig.database = config.databaseName
        pgConfig.user = config.username
        pgConfig.ssl = ssl

        let credentials: [Credential] = [
            .scramSHA256(password: config.password),
            .md5Password(password: config.password),
            .cleartextPassword(password: config.password),
            .trust,
        ]

        var lastError: Error?
        for credential in credentials {
            pgConfig.credential = credential
            do {
                return try PostgresClientKit.Connection(configuration: pgConfig)
            } catch {
                lastError = error
                // Only a wrong credential *type* is worth trying another method;
                // any other failure is terminal.
                if !Self.isCredentialTypeMismatch(error) { break }
            }
        }
        throw lastError ?? PostgresError.connectionFailed("All authentication methods failed.")
    }

    private static func isSSLUnavailable(_ error: Error) -> Bool {
        if let pg = error as? PostgresClientKit.PostgresError, case .sslNotSupported = pg {
            return true
        }
        return false
    }

    // MARK: - Disconnect

    func disconnect() {
        connection?.close()
        connection = nil
        isConnected = false
        isSSLActive = false
        statusMessage = "Disconnected"
    }

    // MARK: - Cancel

    /// Interrupt a query in flight by force-closing the socket from this (other)
    /// thread. PostgresClientKit documents `closeAbruptly()` as safe to call even
    /// while another thread is operating against the connection; it unblocks the
    /// in-flight read, which then throws. PostgresClientKit has no `CancelRequest`
    /// support, so the connection is dead afterwards — the caller must reconnect.
    ///
    /// `DatabaseSession` serialises this against `connect`/`disconnect`, so reading
    /// `connection` here never races those mutating it.
    func cancel() {
        connection?.closeAbruptly()
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
        let statements = SQLStatementSplitter.split(trimmed)

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

    // MARK: - Error formatting

    /// True only for the "you offered the wrong credential type" errors — the
    /// signal that another method in `authMethods` is worth trying. Every other
    /// error is terminal and should be reported to the user as-is.
    private static func isCredentialTypeMismatch(_ error: Error) -> Bool {
        guard let pg = error as? PostgresClientKit.PostgresError else { return false }
        switch pg {
        case .scramSHA256CredentialRequired,
             .md5PasswordCredentialRequired,
             .cleartextPasswordCredentialRequired,
             .trustCredentialRequired:
            return true
        default:
            return false
        }
    }

    /// Turns a connection failure into a message the user can act on.
    ///
    /// PostgresClientKit's `PostgresError` is a bare `enum: Error` with no
    /// `LocalizedError`/`CustomStringConvertible` conformance, so
    /// `error.localizedDescription` yields a useless "The operation couldn't be
    /// completed…" string. The real information lives in the associated values —
    /// most importantly the server's own `Notice` (e.g. "no pg_hba.conf entry
    /// for host …" or "password authentication failed for user …").
    private static func describeConnectionError(_ error: Error?,
                                                host: String,
                                                port: Int,
                                                database: String,
                                                user: String) -> String {
        guard let error = error else {
            return "Could not connect to \(host):\(port)."
        }

        guard let pg = error as? PostgresClientKit.PostgresError else {
            // Some lower-level error — its own description still beats
            // localizedDescription.
            return String(describing: error)
        }

        switch pg {
        case .sqlError(let notice):
            // The server's own words.
            let serverMessage = notice.message ?? "The server rejected the connection."
            var msg = serverMessage
            if let severity = notice.severity { msg = "\(severity): \(msg)" }
            if let detail = notice.detail { msg += "\nDetail: \(detail)" }
            if let hint = notice.hint { msg += "\nHint: \(hint)" }
            // For a "no pg_hba.conf entry" rejection, show the exact line the
            // server's admin would add to let this connection in.
            if let hbaLine = PostgresHBA.suggestedLine(fromServerMessage: serverMessage) {
                msg += "\n\nThe server has no pg_hba.conf rule that permits this login. Add a line like this on the server, then reload it (SELECT pg_reload_conf();):\n\n    \(hbaLine)"
            }
            if let code = notice.code { msg += "\n(SQLSTATE \(code))" }
            return msg

        case .socketError(let cause):
            return "Could not reach \(host):\(port) — \(String(describing: cause))"

        case .sslError(let cause):
            return "SSL/TLS error connecting to \(host):\(port) — \(String(describing: cause))"

        case .sslNotSupported:
            return "The server at \(host):\(port) does not support SSL."

        case .serverError(let description):
            return "Server error from \(host):\(port) — \(description)"

        case .scramSHA256CredentialRequired,
             .md5PasswordCredentialRequired,
             .cleartextPasswordCredentialRequired,
             .trustCredentialRequired:
            // Exhausted every credential type — almost always a wrong
            // username/password.
            return "Authentication failed for user \"\(user)\" on database \"\(database)\" at \(host):\(port). Check the username and password."

        case .unsupportedAuthenticationType(let authenticationType):
            return "The server at \(host):\(port) requires an authentication type SQLTerminal does not support: \(authenticationType)."

        case .invalidUsernameString:
            return "The username \"\(user)\" is not valid for SCRAM authentication."

        case .invalidPasswordString:
            return "The password is not valid for SCRAM authentication."

        default:
            return String(describing: pg)
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
