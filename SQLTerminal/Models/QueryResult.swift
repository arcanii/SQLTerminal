// QueryResult.swift
// SQLTerminal

import Foundation

/// A unified result type every provider returns after executing SQL.
struct QueryResult: Identifiable {
    let id = UUID()
    let columns: [String]
    let rows: [[String]]
    let rowsAffected: Int
    let executionTime: TimeInterval
    let error: String?
    let statementType: StatementType

    enum StatementType {
        case query      // SELECT, PRAGMA, etc. – returns rows
        case mutation   // INSERT, UPDATE, DELETE, CREATE, DROP, etc.
        case error
    }

    /// Convenience: a result that carries only an error.
    static func failure(_ message: String) -> QueryResult {
        QueryResult(
            columns: [],
            rows: [],
            rowsAffected: 0,
            executionTime: 0,
            error: message,
            statementType: .error
        )
    }
}

