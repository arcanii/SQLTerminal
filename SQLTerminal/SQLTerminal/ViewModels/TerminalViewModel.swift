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

        let input = sqlText.trimmingCharacters(in: .whitespacesAndNewlines)
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
        if let dotResult = DotCommandHandler.handle(input) {
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
