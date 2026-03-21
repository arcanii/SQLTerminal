//
//  Untitled.swift
//  SQLTerminal
//
//  Created by Bryan Mark on 21/3/2026.
//

// DotCommandHandler.swift
// SQLTerminal

import Foundation

/// Translates SQLite-style dot-commands into real SQL.
/// Add new commands to the `commands` dictionary.
struct DotCommandHandler {

    /// Returns nil if the input is not a dot-command.
    /// Returns a DotCommandResult if it is.
    static func handle(_ input: String) -> DotCommandResult? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(".") else { return nil }

        // Split into command and optional argument
        let parts = trimmed.split(maxSplits: 1, omittingEmptySubsequences: true,
                                   whereSeparator: { $0.isWhitespace })
        let command = String(parts[0]).lowercased()
        let argument = parts.count > 1 ? String(parts[1]) : nil

        switch command {

        // ── Table & Schema ──

        case ".tables":
            return .sql("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;")

        case ".views":
            return .sql("SELECT name FROM sqlite_master WHERE type='view' ORDER BY name;")

        case ".indexes":
            if let table = argument {
                return .sql("SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='\(table)' ORDER BY name;")
            }
            return .sql("SELECT name, tbl_name FROM sqlite_master WHERE type='index' ORDER BY tbl_name, name;")

        case ".schema":
            if let table = argument {
                return .sql("SELECT sql FROM sqlite_master WHERE name='\(table)';")
            }
            return .sql("SELECT sql FROM sqlite_master WHERE sql IS NOT NULL ORDER BY name;")

        case ".columns":
            if let table = argument {
                return .sql("PRAGMA table_info('\(table)');")
            }
            return .message("Usage: .columns <table_name>")

        // ── Database Info ──

        case ".dbinfo":
            return .multiSQL([
                "SELECT 'SQLite version' AS property, sqlite_version() AS value;",
                "PRAGMA page_size;",
                "PRAGMA page_count;",
                "PRAGMA journal_mode;",
                "PRAGMA wal_checkpoint;",
            ])

        case ".size":
            return .sql("SELECT page_count * page_size AS size_bytes FROM pragma_page_count(), pragma_page_size();")

        // ── Pragmas ──

        case ".fk", ".foreignkeys":
            if let table = argument {
                return .sql("PRAGMA foreign_key_list('\(table)');")
            }
            return .message("Usage: .fk <table_name>")

        case ".journal":
            return .sql("PRAGMA journal_mode;")

        case ".encoding":
            return .sql("PRAGMA encoding;")

        // ── Data Inspection ──

        case ".count":
            if let table = argument {
                return .sql("SELECT COUNT(*) AS row_count FROM \"\(table)\";")
            }
            return .message("Usage: .count <table_name>")

        case ".first":
            if let table = argument {
                return .sql("SELECT * FROM \"\(table)\" LIMIT 10;")
            }
            return .message("Usage: .first <table_name>")

        case ".last":
            if let table = argument {
                return .sql("SELECT * FROM \"\(table)\" ORDER BY rowid DESC LIMIT 10;")
            }
            return .message("Usage: .last <table_name>")

        // ── Help ──

        case ".help":
            return .message(helpText)
            
            
        // -- Special SQL Terminal commands
        case ".clear":
                    return .clear
            
        default:
            return .message("Unknown command: \(command)\nType .help for available commands.")
        }
    }

    // MARK: - Help text

    private static let helpText = """
    Available dot-commands:

    Tables & Schema
      .tables                 List all tables
      .views                  List all views
      .indexes [table]        List indexes (optionally for a table)
      .schema [table]         Show CREATE statements
      .columns <table>        Show column info for a table

    Database Info
      .dbinfo                 Show database properties
      .size                   Show database size in bytes
      .journal                Show journal mode
      .encoding               Show database encoding

    Data Inspection
      .count <table>          Count rows in a table
      .first <table>          Show first 10 rows
      .last <table>           Show last 10 rows

    Foreign Keys
      .fk <table>             Show foreign keys for a table
    
    Terminal
      .clear                  Clear the terminal output
    
    Other
      .help                   Show this help
    """
}

// MARK: - Result type

enum DotCommandResult {
    /// A single SQL statement to execute normally.
    case sql(String)

    /// Multiple SQL statements to execute in sequence.
    case multiSQL([String])

    /// A plain text message to display (help, errors, usage).
    case message(String)
    
    // Special terminal commands
    case clear

}
