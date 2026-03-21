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
// SQLiteProvider.swift

import Foundation
import SQLite3

final class SQLiteProvider: DatabaseProvider {
    
    let engine: DatabaseEngine = .sqlite
    private(set) var isConnected = false
    private(set) var statusMessage = "Disconnected"
    
    private var db: OpaquePointer?
    private var accessedURL: URL?
    
    deinit { disconnect() }
    
    // MARK: - Connect
    
    func connect(with connection: DatabaseConnection) throws {
        disconnect()
        
        let path = (connection.filePath as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: path)
        
        // Start accessing the security-scoped resource (sandbox)
        let gained = url.startAccessingSecurityScopedResource()
        if gained {
            accessedURL = url
        }
        
        // Make sure the parent directory exists
        let dir = url.deletingLastPathComponent().path
        if !FileManager.default.fileExists(atPath: dir) {
            throw SQLiteError.connectionFailed(
                "Directory does not exist: \(dir)"
            )
        }
        
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(path, &db, flags, nil)
        
        guard rc == SQLITE_OK, db != nil else {
            let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) }
            ?? "Unknown error (code \(rc))"
            disconnect()
            throw SQLiteError.connectionFailed(msg)
        }
        
        isConnected = true
        let name = (path as NSString).lastPathComponent
        statusMessage = "Connected to \(name)"
    }
    
    // MARK: - Disconnect
    
    func disconnect() {
        if let db = db {
            sqlite3_close_v2(db)
        }
        db = nil
        isConnected = false
        statusMessage = "Disconnected"
        
        // Release sandbox access
        accessedURL?.stopAccessingSecurityScopedResource()
        accessedURL = nil
    }
    

    // MARK: - Execute

    func execute(sql: String) -> QueryResult {
        guard let db = db else {
            return .failure("No database connection.")
        }

        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure("Empty query.")
        }

        let start = CFAbsoluteTimeGetCurrent()

        var allColumns: [String] = []
        var allRows: [[String]] = []
        var totalRowsAffected = 0
        var lastStatementWasQuery = false

        // Convert to a stable UTF8 buffer that persists across the loop
        let utf8 = Array(trimmed.utf8) + [0]  // null-terminated

        return utf8.withUnsafeBufferPointer { buffer in
            guard let basePointer = buffer.baseAddress else {
                return QueryResult.failure("Internal error.")
            }

            var current: UnsafePointer<CChar>? = UnsafeRawPointer(basePointer)
                .assumingMemoryBound(to: CChar.self)

            while true {
                // Skip whitespace and semicolons
                while let c = current, c.pointee != 0,
                      (c.pointee == 0x20 || c.pointee == 0x0A || c.pointee == 0x0D ||
                       c.pointee == 0x09 || c.pointee == 0x3B) {
                    current = c.advanced(by: 1)
                }

                // Check if we've reached the end
                guard let c = current, c.pointee != 0 else { break }

                var stmt: OpaquePointer?
                var tail: UnsafePointer<CChar>?

                let prepareRC = sqlite3_prepare_v2(db, c, -1, &stmt, &tail)

                guard prepareRC == SQLITE_OK else {
                    let msg = String(cString: sqlite3_errmsg(db))
                    sqlite3_finalize(stmt)
                    let elapsed = CFAbsoluteTimeGetCurrent() - start
                    return QueryResult(
                        columns: allColumns,
                        rows: allRows,
                        rowsAffected: totalRowsAffected,
                        executionTime: elapsed,
                        error: msg,
                        statementType: .error
                    )
                }

                // nil stmt means nothing to prepare (empty/whitespace)
                guard let statement = stmt else { break }

                // Collect columns
                let columnCount = Int(sqlite3_column_count(statement))
                if columnCount > 0 {
                    lastStatementWasQuery = true
                    allColumns = []
                    allRows = []
                    for i in 0..<columnCount {
                        let name = sqlite3_column_name(statement, Int32(i))
                            .map { String(cString: $0) } ?? "col\(i)"
                        allColumns.append(name)
                    }
                } else {
                    lastStatementWasQuery = false
                }

                // Step through rows
                var stepRC = sqlite3_step(statement)

                while stepRC == SQLITE_ROW {
                    var row: [String] = []
                    for i in 0..<columnCount {
                        if let text = sqlite3_column_text(statement, Int32(i)) {
                            row.append(String(cString: text))
                        } else {
                            row.append("NULL")
                        }
                    }
                    allRows.append(row)
                    stepRC = sqlite3_step(statement)
                }

                totalRowsAffected += Int(sqlite3_changes(db))
                sqlite3_finalize(statement)

                if stepRC != SQLITE_DONE {
                    let msg = String(cString: sqlite3_errmsg(db))
                    let elapsed = CFAbsoluteTimeGetCurrent() - start
                    return QueryResult(
                        columns: allColumns,
                        rows: allRows,
                        rowsAffected: totalRowsAffected,
                        executionTime: elapsed,
                        error: msg,
                        statementType: .error
                    )
                }

                // Advance to what's after this statement
                current = tail
            }

            let elapsed = CFAbsoluteTimeGetCurrent() - start

            return QueryResult(
                columns: allColumns,
                rows: allRows,
                rowsAffected: totalRowsAffected,
                executionTime: elapsed,
                error: nil,
                statementType: lastStatementWasQuery ? .query : .mutation
            )
        }
    }

   
    
}
enum SQLiteError: LocalizedError {
    case connectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let msg):
            return "SQLite connection failed: \(msg)"
        }
    }
}

