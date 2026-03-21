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
// DotCommandHandler.swift
// SQLTerminal

import Foundation

struct DotCommandHandler {

    static func handle(_ input: String, engine: DatabaseEngine = .sqlite) -> DotCommandResult? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(".") else { return nil }

        let parts = trimmed.split(maxSplits: 1, omittingEmptySubsequences: true,
                                   whereSeparator: { $0.isWhitespace })
        let command = String(parts[0]).lowercased()
        let argument = parts.count > 1 ? String(parts[1]) : nil

        switch command {

        // ── Tables & Schema ──

        case ".tables":
            switch engine {
            case .sqlite:
                return .sql("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;")
            case .postgres:
                return .sql("SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename;")
            }

        case ".views":
            switch engine {
            case .sqlite:
                return .sql("SELECT name FROM sqlite_master WHERE type='view' ORDER BY name;")
            case .postgres:
                return .sql("SELECT viewname FROM pg_views WHERE schemaname = 'public' ORDER BY viewname;")
            }

        case ".indexes":
            switch engine {
            case .sqlite:
                if let table = argument {
                    return .sql("SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='\(table)' ORDER BY name;")
                }
                return .sql("SELECT name, tbl_name FROM sqlite_master WHERE type='index' ORDER BY tbl_name, name;")
            case .postgres:
                if let table = argument {
                    return .sql("SELECT indexname, indexdef FROM pg_indexes WHERE tablename = '\(table)' ORDER BY indexname;")
                }
                return .sql("SELECT tablename, indexname FROM pg_indexes WHERE schemaname = 'public' ORDER BY tablename, indexname;")
            }

        case ".schema":
            switch engine {
            case .sqlite:
                if let table = argument {
                    return .sql("SELECT sql FROM sqlite_master WHERE name='\(table)';")
                }
                return .sql("SELECT sql FROM sqlite_master WHERE sql IS NOT NULL ORDER BY name;")
            case .postgres:
                if let table = argument {
                    return .sql("""
                        SELECT column_name, data_type, is_nullable, column_default
                        FROM information_schema.columns
                        WHERE table_schema = 'public' AND table_name = '\(table)'
                        ORDER BY ordinal_position;
                    """)
                }
                return .sql("SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' ORDER BY table_name;")
            }

        case ".columns":
            if let table = argument {
                switch engine {
                case .sqlite:
                    return .sql("PRAGMA table_info('\(table)');")
                case .postgres:
                    return .sql("""
                        SELECT column_name, data_type, is_nullable, column_default
                        FROM information_schema.columns
                        WHERE table_schema = 'public' AND table_name = '\(table)'
                        ORDER BY ordinal_position;
                    """)
                }
            }
            return .message("Usage: .columns <table_name>")

        // ── Database Info ──

        case ".dbinfo":
            switch engine {
            case .sqlite:
                return .multiSQL([
                    "SELECT 'SQLite version' AS property, sqlite_version() AS value;",
                    "PRAGMA page_size;",
                    "PRAGMA page_count;",
                    "PRAGMA journal_mode;",
                ])
            case .postgres:
                return .multiSQL([
                    "SELECT version();",
                    "SELECT current_database() AS database, current_user AS user, inet_server_addr() AS host, inet_server_port() AS port;",
                    "SELECT pg_size_pretty(pg_database_size(current_database())) AS database_size;",
                ])
            }

        case ".size":
            switch engine {
            case .sqlite:
                return .sql("SELECT page_count * page_size AS size_bytes FROM pragma_page_count(), pragma_page_size();")
            case .postgres:
                return .sql("SELECT pg_size_pretty(pg_database_size(current_database())) AS database_size;")
            }

        // ── Foreign Keys ──

        case ".fk", ".foreignkeys":
            if let table = argument {
                switch engine {
                case .sqlite:
                    return .sql("PRAGMA foreign_key_list('\(table)');")
                case .postgres:
                    return .sql("""
                        SELECT conname AS constraint_name,
                               conrelid::regclass AS table_name,
                               a.attname AS column_name,
                               confrelid::regclass AS foreign_table,
                               af.attname AS foreign_column
                        FROM pg_constraint c
                        JOIN pg_attribute a ON a.attnum = ANY(c.conkey) AND a.attrelid = c.conrelid
                        JOIN pg_attribute af ON af.attnum = ANY(c.confkey) AND af.attrelid = c.confrelid
                        WHERE c.contype = 'f' AND c.conrelid::regclass::text = '\(table)';
                    """)
                }
            }
            return .message("Usage: .fk <table_name>")

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
                switch engine {
                case .sqlite:
                    return .sql("SELECT * FROM \"\(table)\" ORDER BY rowid DESC LIMIT 10;")
                case .postgres:
                    return .sql("SELECT * FROM \"\(table)\" ORDER BY ctid DESC LIMIT 10;")
                }
            }
            return .message("Usage: .last <table_name>")

        // ── Postgres specific ──

        case ".schemas":
            switch engine {
            case .sqlite:
                return .message(".schemas is only available for PostgreSQL.")
            case .postgres:
                return .sql("SELECT schema_name FROM information_schema.schemata ORDER BY schema_name;")
            }

        case ".databases":
            switch engine {
            case .sqlite:
                return .message(".databases is only available for PostgreSQL.")
            case .postgres:
                return .sql("SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY datname;")
            }

        // ── SQLite specific ──

        case ".journal":
            switch engine {
            case .sqlite:
                return .sql("PRAGMA journal_mode;")
            case .postgres:
                return .message(".journal is only available for SQLite.")
            }

        case ".encoding":
            switch engine {
            case .sqlite:
                return .sql("PRAGMA encoding;")
            case .postgres:
                return .sql("SHOW server_encoding;")
            }

        // ── Terminal ──

        case ".clear":
            return .clear

        // ── Help ──

        case ".help":
            return .message(engine == .sqlite ? sqliteHelpText : postgresHelpText)

        default:
            return .message("Unknown command: \(command)\nType .help for available commands.")
        }
    }

    // MARK: - Help texts

    private static let sqliteHelpText = """
    Available dot-commands (SQLite):

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

    private static let postgresHelpText = """
    Available dot-commands (PostgreSQL):

    Tables & Schema
      .tables                 List all tables in public schema
      .views                  List all views in public schema
      .indexes [table]        List indexes (optionally for a table)
      .schema [table]         Show column definitions
      .columns <table>        Show column info for a table

    Database Info
      .dbinfo                 Show database properties
      .size                   Show database size
      .encoding               Show server encoding
      .schemas                List all schemas
      .databases              List all databases

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
    case sql(String)
    case multiSQL([String])
    case message(String)
    case clear
}

