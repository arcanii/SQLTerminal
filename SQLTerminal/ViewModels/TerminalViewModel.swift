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

// TerminalViewModel.swift
// SQLTerminal

import SwiftUI
import Combine

@MainActor
final class TerminalViewModel: ObservableObject {

    // MARK: - Published state

    @Published var sqlText: String = ""
    @Published var history: [HistoryEntry] = []
    @Published var isShowingConnectionSheet = true
    @Published var connectionInfo: DatabaseConnection?
    @Published var isConnected = false
    /// Whether the active connection is encrypted (SSL/TLS) — drives the lock icon.
    @Published var isSSLActive = false

    /// A query is executing on the background session. Drives the spinner and the
    /// Cancel affordance, and gates a second concurrent execution.
    @Published var isRunning = false
    /// A connect / reconnect is in progress (also blocking I/O, but not cancellable
    /// in a way that can interrupt a stuck socket, so no Cancel is offered).
    @Published var isConnecting = false

    /// When on, statements the classifier sees as writes/DDL are blocked before
    /// they reach the database. A per-window guard against prod accidents.
    @Published var isReadOnly = false

    /// Set when a destructive statement is awaiting the user's confirmation; the
    /// view presents a dialog bound to this.
    @Published var pendingConfirmation: PendingConfirmation?

    /// Whether a transaction is open (tracked heuristically from the
    /// BEGIN/COMMIT/ROLLBACK statements that run). Reset by any (re)connect.
    @Published var inTransaction = false

    // MARK: - Command history

    private var commandHistory: [String] = []
    private var historyIndex: Int = -1
    private var savedCurrentInput: String = ""

    // MARK: - Session

    /// Runs all blocking database work off the main thread. One per view model,
    /// so each window's session is fully independent.
    private let session = DatabaseSession(label: "com.sqlterminal.session.\(UUID().uuidString)")

    /// The in-flight execute / reconnect task, if any. Cancelling it interrupts a
    /// running query (see `DatabaseSession`).
    private var runningTask: Task<Void, Never>?

    // MARK: - Connection

    /// Connect off the main thread. Returns whether the connection succeeded; the
    /// detailed failure reason is appended to history (as before).
    @discardableResult
    func connect(with config: DatabaseConnection) async -> Bool {
        isConnecting = true
        defer { isConnecting = false }
        do {
            try await session.connect(config)
            connectionInfo = config
            isConnected = true
            isSSLActive = session.isSSLActive
            inTransaction = false
            appendHistory(.system("Connected to \(config.displayName)"))
            return true
        } catch {
            connectionInfo = nil
            isConnected = false
            isSSLActive = false
            appendHistory(.error(error.localizedDescription))
            return false
        }
    }

    func disconnect() {
        teardownConnection()
        appendHistory(.system("Disconnected."))
    }

    func disconnectAndPromptReconnect() {
        teardownConnection()
        history.removeAll()
        isShowingConnectionSheet = true
    }

    /// Stop any running query and close the connection off the main thread.
    /// Marks state disconnected *first* so a cancelled query's recovery path
    /// knows not to reconnect.
    private func teardownConnection() {
        isConnected = false
        isSSLActive = false
        inTransaction = false
        connectionInfo = nil
        runningTask?.cancel()
        runningTask = nil
        session.cancel()                 // unblock anything in flight on the queue
        let session = self.session
        Task.detached { await session.disconnect() }
    }

    /// Switch the active connection to another database on the same server
    /// (Postgres binds one database per connection). Reuses the current session's
    /// credentials, so there is no re-prompt. Runs off the main thread.
    func reconnectToDatabase(_ dbName: String) async {
        guard let previousConfig = connectionInfo else {
            appendHistory(.error("No active connection to switch from."))
            return
        }

        var config = previousConfig
        config.databaseName = dbName

        do {
            // `session.connect` quietly tears down the current connection first.
            try await session.connect(config)
            connectionInfo = config
            isConnected = true
            isSSLActive = session.isSSLActive
            inTransaction = false
            appendHistory(.system("Switched to database \"\(dbName)\"."))
        } catch {
            // The switch failed (no access, no such database, …). Report a clear
            // reason and quietly restore the previous database — no reconnect
            // chatter.
            let reason = friendlySwitchError(error, database: dbName)
            do {
                try await session.connect(previousConfig)
                connectionInfo = previousConfig
                isConnected = true
                isSSLActive = session.isSSLActive
                inTransaction = false
                appendHistory(.error("\(reason) Still connected to \"\(previousConfig.databaseName)\"."))
            } catch {
                connectionInfo = nil
                isConnected = false
                isSSLActive = false
                appendHistory(.error("\(reason) The previous connection was also lost — please reconnect."))
            }
        }
    }

    /// Maps a failed database switch to a clear, human-readable reason. Matches
    /// on the SQLSTATE code (which Postgres does not localize) with the English
    /// message text as a fallback.
    private func friendlySwitchError(_ error: Error, database: String) -> String {
        let detail = error.localizedDescription
        if detail.contains("42501") || detail.localizedCaseInsensitiveContains("permission denied for database") {
            return "You don't have access to database \"\(database)\"."
        }
        if detail.contains("3D000") || detail.localizedCaseInsensitiveContains("does not exist") {
            return "Database \"\(database)\" does not exist."
        }
        return "Couldn't switch to \"\(database)\": \(detail)"
    }



    // MARK: - Command history navigation

    func navigateHistoryUp() {
        guard !commandHistory.isEmpty else { return }

        // First time pressing up: save whatever is currently typed
        if historyIndex == -1 {
            savedCurrentInput = sqlText
            historyIndex = commandHistory.count - 1
        } else if historyIndex > 0 {
            historyIndex -= 1
        }

        sqlText = commandHistory[historyIndex]
    }

    func navigateHistoryDown() {
        guard historyIndex != -1 else { return }

        if historyIndex < commandHistory.count - 1 {
            historyIndex += 1
            sqlText = commandHistory[historyIndex]
        } else {
            // Back to the bottom — restore what the user was typing
            historyIndex = -1
            sqlText = savedCurrentInput
        }
    }

    // MARK: - Query execution (called by ⌘E)

    /// Run the whole editor (⌘E), clearing it afterwards.
    func executeCurrentQuery() {
        runText(sqlText, clearEditorAfterwards: true)
    }

    /// Run just `snippet` — the selected SQL, or the statement under the cursor —
    /// without clearing the editor (⌘↩). Falls back to the whole editor when the
    /// snippet is empty (e.g. nothing selected and the cursor is between statements).
    func executeSnippet(_ snippet: String?) {
        let trimmed = snippet?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            executeCurrentQuery()
        } else {
            runText(trimmed, clearEditorAfterwards: false)
        }
    }

    private func runText(_ rawText: String, clearEditorAfterwards: Bool, recordInHistory: Bool = true) {
        // One operation at a time; ignore while a query or connect is busy.
        guard !isRunning, !isConnecting else { return }
        guard isConnected else {
            appendHistory(.error("Not connected to any database."))
            return
        }

        let input = Self.normalizingSmartCharacters(rawText)
        guard !input.isEmpty else { return }

        // Save to command history (avoid duplicating the last entry)
        if commandHistory.last != input {
            commandHistory.append(input)
        }
        historyIndex = -1
        savedCurrentInput = ""

        // Echo the input; clear the editor only for a whole-editor run.
        appendHistory(.input(input))
        if recordInHistory {
            QueryHistoryStore.record(input)   // persistent, app-wide, searchable
        }
        if clearEditorAfterwards {
            sqlText = ""
        }

        // Dot-commands are parsed on the main thread (pure + instant); only the
        // ones that actually hit the database are dispatched off-main.
        let currentEngine = connectionInfo?.engine ?? .sqlite
        if let dotResult = DotCommandHandler.handle(input, engine: currentEngine) {
            switch dotResult {
            case .sql(let sql):
                guardedRun([sql])

            case .multiSQL(let statements):
                guardedRun(statements)

            case .reconnect(let dbName):
                runReconnect(dbName)

            case .message(let text):
                appendHistory(.system(text))

            case .clear:
                history.removeAll()
            }
        } else {
            // Regular SQL — the provider splits multi-statement input itself.
            guardedRun([input])
        }
    }

    /// Trim and normalise the macOS "smart" quotes/dashes that would break SQL.
    private static func normalizingSmartCharacters(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{201C}", with: "\"")  // left double "
            .replacingOccurrences(of: "\u{201D}", with: "\"")  // right double "
            .replacingOccurrences(of: "\u{2018}", with: "'")   // left single '
            .replacingOccurrences(of: "\u{2019}", with: "'")   // right single '
            .replacingOccurrences(of: "\u{2013}", with: "-")   // en dash –
            .replacingOccurrences(of: "\u{2014}", with: "-")   // em dash —
    }

    /// Apply the read-only block and the destructive-statement confirmation before
    /// handing `statements` to the executor. Each element is split + classified, so
    /// this works for both single input and the `.multiSQL` dot-command batch.
    private func guardedRun(_ statements: [String]) {
        let infos = statements.flatMap { SQLStatementClassifier.classifyAll($0) }

        // Read-only takes precedence: block the first write outright.
        if isReadOnly, let write = infos.first(where: { $0.kind == .write }) {
            appendHistory(.error("Read-only mode is on — \(write.leadingKeyword) is blocked. Toggle it off in the toolbar to run writes."))
            return
        }

        // Otherwise, confirm anything destructive before running.
        let destructive = infos.filter(\.isDestructive)
        if !destructive.isEmpty {
            pendingConfirmation = PendingConfirmation(
                statements: statements,
                message: destructiveWarning(for: destructive)
            )
            return
        }

        runStatements(statements)
    }

    /// Proceed with a previously-flagged destructive run.
    func confirmPendingExecution() {
        guard let pending = pendingConfirmation else { return }
        pendingConfirmation = nil
        runStatements(pending.statements)
    }

    /// Abandon a flagged destructive run.
    func cancelPendingExecution() {
        guard pendingConfirmation != nil else { return }
        pendingConfirmation = nil
        appendHistory(.system("Cancelled — destructive statement not run."))
    }

    private func destructiveWarning(for infos: [SQLStatementInfo]) -> String {
        let labels = infos.map { info -> String in
            switch info.leadingKeyword {
            case "DROP", "TRUNCATE": return info.leadingKeyword
            default:                 return "\(info.leadingKeyword) without WHERE"
            }
        }
        let unique = Array(NSOrderedSet(array: labels)) as? [String] ?? labels
        return "This runs a destructive statement that can't be undone: \(unique.joined(separator: ", ")). Run it anyway?"
    }

    /// Execute `statements` one at a time on the background session, appending a
    /// result (or error) per statement — matching the previous synchronous
    /// behaviour, including continuing past a failed statement in a `.multiSQL`
    /// batch. If the task is cancelled mid-flight, the running statement is
    /// interrupted and a single "cancelled" notice is shown instead.
    private func runStatements(_ statements: [String]) {
        // Set synchronously (before the task is scheduled) so a second ⌘E can't
        // slip past the `guard !isRunning` before the task body starts.
        isRunning = true
        runningTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.isRunning = false
                self.runningTask = nil
            }

            var wasCancelled = false
            for sql in statements {
                if Task.isCancelled { wasCancelled = true; break }
                let result = await self.session.execute(sql)
                // A cancel unblocks the query with a throwaway error; discard it.
                if Task.isCancelled { wasCancelled = true; break }
                if let error = result.error {
                    self.appendHistory(.error(error))
                } else {
                    self.appendHistory(.result(result))
                }
            }

            if wasCancelled {
                // Stay quiet during teardown (isConnected already false).
                if self.isConnected {
                    self.appendHistory(.system("Query cancelled."))
                }
                await self.recoverAfterCancel()
            } else {
                self.updateTransactionState(after: statements)
            }
        }
    }

    /// Drive `reconnectToDatabase` as the in-flight task with a connecting (not
    /// cancellable-query) indicator.
    private func runReconnect(_ dbName: String) {
        // Set synchronously so the busy-guard is effective before the task starts.
        isConnecting = true
        runningTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.isConnecting = false
                self.runningTask = nil
            }
            await self.reconnectToDatabase(dbName)
        }
    }

    /// After a successful cancel, Postgres' socket has been force-closed and the
    /// connection is dead — transparently reconnect (reusing the session's
    /// credentials) so the window stays usable. SQLite's interrupt leaves the
    /// connection intact, so nothing is needed there.
    private func recoverAfterCancel() async {
        guard isConnected,
              let config = connectionInfo,
              config.engine == .postgres else { return }
        do {
            try await session.connect(config)
            isSSLActive = session.isSSLActive
            inTransaction = false   // the force-closed transaction is gone
            appendHistory(.system("Reconnected to \(config.displayName)."))
        } catch {
            isConnected = false
            isSSLActive = false
            inTransaction = false
            appendHistory(.error("The connection was closed to cancel the query and could not be re-established: \(error.localizedDescription)"))
        }
    }

    /// Cancel a running query (no effect on a connect/reconnect, which can't be
    /// interrupted cleanly). Invoked by the Cancel toolbar button / ⌘.
    func cancelRunningQuery() {
        guard isRunning else { return }
        runningTask?.cancel()   // fires DatabaseSession's cancellation handler
    }

    // MARK: - Transactions

    /// Open a transaction. Convenience for the toolbar; equivalent to typing BEGIN.
    func beginTransaction() { runText("BEGIN", clearEditorAfterwards: false, recordInHistory: false) }

    /// Commit the open transaction.
    func commitTransaction() { runText("COMMIT", clearEditorAfterwards: false, recordInHistory: false) }

    /// Roll back the open transaction.
    func rollbackTransaction() { runText("ROLLBACK", clearEditorAfterwards: false, recordInHistory: false) }

    /// Update `inTransaction` from the transaction-control statements that ran.
    /// Heuristic: the last BEGIN/COMMIT/ROLLBACK in the batch wins. Good enough
    /// for the common cases without a server round-trip to read the real status;
    /// a wrong guess self-corrects on the next statement (Postgres reports an
    /// aborted transaction) and on any reconnect.
    private func updateTransactionState(after statements: [String]) {
        let ran = statements.flatMap { SQLStatementSplitter.split($0) }
        for stmt in ran {
            switch SQLStatementClassifier.classify(stmt).leadingKeyword {
            case "BEGIN", "START":
                inTransaction = true
            case "COMMIT", "ROLLBACK", "END", "ABORT":
                inTransaction = false
            default:
                break
            }
        }
    }

    // MARK: - Schema browsing

    /// Table names for the current connection (public schema for Postgres), run as
    /// background metadata — off-main, no history echo, not task-cancellable so it
    /// never tears down the live connection.
    func fetchTableNames() async -> [String] {
        guard isConnected, let engine = connectionInfo?.engine else { return [] }
        let sql: String
        switch engine {
        case .postgres:
            sql = "SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename;"
        case .sqlite:
            sql = "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name;"
        }
        let result = await session.executeUncancellable(sql)
        guard result.error == nil else { return [] }
        return result.rows.compactMap { $0.first }
    }

    /// Column (name, type) pairs for `table`.
    func fetchColumns(forTable table: String) async -> [SchemaColumn] {
        guard isConnected, let engine = connectionInfo?.engine else { return [] }
        let literal = table.replacingOccurrences(of: "'", with: "''")
        let sql: String
        switch engine {
        case .postgres:
            sql = """
            SELECT column_name, data_type FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name = '\(literal)'
            ORDER BY ordinal_position;
            """
        case .sqlite:
            sql = "PRAGMA table_info('\(literal)');"   // cols: cid, name, type, …
        }
        let result = await session.executeUncancellable(sql)
        guard result.error == nil else { return [] }
        switch engine {
        case .postgres:
            return result.rows.map { SchemaColumn(name: $0.first ?? "", type: $0.count > 1 ? $0[1] : "") }
        case .sqlite:
            return result.rows.map { SchemaColumn(name: $0.count > 1 ? $0[1] : "", type: $0.count > 2 ? $0[2] : "") }
        }
    }

    /// Put a starter `SELECT` for `table` into the editor (does not run it).
    func insertSelectStatement(forTable table: String) {
        sqlText = "SELECT * FROM \(Self.quotedIdentifier(table)) LIMIT 100;"
    }

    /// Run a quick preview of `table` (does not touch the editor).
    func previewTable(_ table: String) {
        runText("SELECT * FROM \(Self.quotedIdentifier(table)) LIMIT 100", clearEditorAfterwards: false)
    }

    /// Double-quote an identifier (works for both engines), escaping any quotes.
    private static func quotedIdentifier(_ name: String) -> String {
        "\"" + name.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: - History

    private func appendHistory(_ entry: HistoryEntry) {
        history.append(entry)
    }
}

// MARK: - Pending destructive confirmation

/// A destructive run held back until the user confirms it.
struct PendingConfirmation: Identifiable {
    let id = UUID()
    let statements: [String]
    let message: String
}

// MARK: - Schema

/// A column in the schema sidebar.
struct SchemaColumn: Identifiable, Hashable {
    let name: String
    let type: String
    var id: String { name }
}

// MARK: - History entry model

enum HistoryEntry: Identifiable {
    case input(String)
    case result(QueryResult)
    case error(String)
    case system(String)

    var id: UUID {
        switch self {
        case .result(let r): return r.id
        default: return UUID()
        }
    }
}
