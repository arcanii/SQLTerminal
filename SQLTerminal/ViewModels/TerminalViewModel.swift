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

    // MARK: - Command history

    private var commandHistory: [String] = []
    private var historyIndex: Int = -1
    private var savedCurrentInput: String = ""

    // MARK: - Provider

    private var provider: DatabaseProvider?

    // MARK: - Connection

    func connect(with config: DatabaseConnection) {
        let newProvider = DatabaseProviderFactory.provider(for: config.engine)
        do {
            try newProvider.connect(with: config)
            self.provider = newProvider
            self.connectionInfo = config
            self.isConnected = true
            appendHistory(
                .system("Connected to \(config.displayName)")
            )
        } catch {
            appendHistory(.error(error.localizedDescription))
        }
    }

    func disconnect() {
        provider?.disconnect()
        provider = nil
        connectionInfo = nil
        isConnected = false
        appendHistory(.system("Disconnected."))
    }
    
    func disconnectAndPromptReconnect() {
        provider?.disconnect()
        provider = nil
        connectionInfo = nil
        isConnected = false
        history.removeAll()
        isShowingConnectionSheet = true
    }
    
    func reconnectToDatabase(_ dbName: String) {
        guard var config = connectionInfo else {
            appendHistory(.error("No active connection to switch from."))
            return
        }

        // Disconnect current
        provider?.disconnect()
        provider = nil
        isConnected = false

        appendHistory(.system("Switching to database: \(dbName)..."))

        // Update the database name
        config.databaseName = dbName

        // Reconnect
        let newProvider = DatabaseProviderFactory.provider(for: config.engine)
        do {
            try newProvider.connect(with: config)
            self.provider = newProvider
            self.connectionInfo = config
            self.isConnected = true
            appendHistory(.system("Connected to \(config.displayName)"))
        } catch {
            appendHistory(.error("Failed to connect to \(dbName): \(error.localizedDescription)"))
            // Try to reconnect to the old database
            if let oldConfig = connectionInfo {
                appendHistory(.system("Attempting to reconnect to previous database..."))
                let fallback = DatabaseProviderFactory.provider(for: oldConfig.engine)
                do {
                    try fallback.connect(with: oldConfig)
                    self.provider = fallback
                    self.isConnected = true
                    appendHistory(.system("Reconnected to \(oldConfig.displayName)"))
                } catch {
                    appendHistory(.error("Could not reconnect: \(error.localizedDescription)"))
                }
            }
        }
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

    func executeCurrentQuery() {
        guard let provider = provider, provider.isConnected else {
            appendHistory(.error("Not connected to any database."))
            return
        }
        
        // Fix smart quotes/dashes that macOS may have inserted
        let input = sqlText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{201C}", with: "\"")  // left double "
            .replacingOccurrences(of: "\u{201D}", with: "\"")  // right double "
            .replacingOccurrences(of: "\u{2018}", with: "'")   // left single '
            .replacingOccurrences(of: "\u{2019}", with: "'")   // right single '
            .replacingOccurrences(of: "\u{2013}", with: "-")   // en dash –
            .replacingOccurrences(of: "\u{2014}", with: "-")   // em dash —
        
        guard !input.isEmpty else { return }

        // Save to command history (avoid duplicating the last entry)
        if commandHistory.last != input {
            commandHistory.append(input)
        }
        historyIndex = -1
        savedCurrentInput = ""

        // Echo the input
        appendHistory(.input(input))

        // Check if it's a dot-command
        let currentEngine = provider.engine
        if let dotResult = DotCommandHandler.handle(input, engine: currentEngine) {
            switch dotResult {
            case .sql(let sql):
                let result = provider.execute(sql: sql)
                if let error = result.error {
                    appendHistory(.error(error))
                } else {
                    appendHistory(.result(result))
                }

            case .multiSQL(let statements):
                for sql in statements {
                    let result = provider.execute(sql: sql)
                    if let error = result.error {
                        appendHistory(.error(error))
                    } else {
                        appendHistory(.result(result))
                    }
                }
     
            case .reconnect(let dbName):
                reconnectToDatabase(dbName)


            case .message(let text):
                appendHistory(.system(text))

            case .clear:
                history.removeAll()
            }
        } else {
            // Regular SQL
            let result = provider.execute(sql: input)
            if let error = result.error {
                appendHistory(.error(error))
            } else {
                appendHistory(.result(result))
            }
        }

        // Clear the editor after execution
        sqlText = ""
    }

    // MARK: - History

    private func appendHistory(_ entry: HistoryEntry) {
        history.append(entry)
    }
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
