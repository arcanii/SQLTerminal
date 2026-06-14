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
            if let hbaLine = Self.suggestedHBALine(fromServerMessage: serverMessage) {
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

    /// If `message` is a Postgres "no pg_hba.conf entry for host …" rejection,
    /// returns the pg_hba.conf line that would permit the connection. Postgres
    /// phrases the rejection as:
    ///
    ///     no pg_hba.conf entry for host "ADDR", user "USER", database "DB", no encryption
    ///
    /// so the three quoted values are exactly the fields a `host` rule needs.
    private static func suggestedHBALine(fromServerMessage message: String) -> String? {
        guard message.contains("no pg_hba.conf entry") else { return nil }

        let quoted = quotedValues(in: message)
        guard quoted.count >= 3 else { return nil }

        let rawAddress = quoted[0]
        let user = quoted[1]
        let database = quoted[2]

        // Strip any IPv6 zone index (e.g. "%en0") — it isn't valid in pg_hba.conf.
        let address = String(rawAddress.split(separator: "%").first ?? Substring(rawAddress))

        // This client always connects over TCP, so we expect an IP literal; if
        // it isn't one, don't risk suggesting a malformed rule.
        guard address.contains(".") || address.contains(":") else { return nil }

        // Single-host CIDR: /32 for IPv4, /128 for IPv6.
        let cidr = address.contains(":") ? "\(address)/128" : "\(address)/32"

        return "host    \(database)    \(user)    \(cidr)    scram-sha-256"
    }

    /// The substrings enclosed in double quotes, in order of appearance.
    private static func quotedValues(in string: String) -> [String] {
        var values: [String] = []
        var current = ""
        var inQuote = false
        for ch in string {
            if ch == "\"" {
                if inQuote { values.append(current); current = "" }
                inQuote.toggle()
            } else if inQuote {
                current.append(ch)
            }
        }
        return values
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
