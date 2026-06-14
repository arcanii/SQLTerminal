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
// SQLStatementClassifier.swift
// SQLTerminal / SQLCore

import Foundation

/// Whether a statement reads, mutates, or just controls the session/transaction.
nonisolated enum SQLStatementKind: Equatable {
    case read      // SELECT, EXPLAIN, SHOW, … — returns/inspects data
    case write     // INSERT/UPDATE/DELETE/DDL/GRANT/… — mutates data or schema
    case neutral   // BEGIN/COMMIT/SET/… or unrecognised — neither blocked nor confirmed
}

/// What we learned about a single statement.
nonisolated struct SQLStatementInfo: Equatable {
    /// Upper-cased leading keyword (e.g. `SELECT`, `DROP`), or "" if empty.
    let leadingKeyword: String
    let kind: SQLStatementKind
    /// True for statements worth a second look: `DROP`, `TRUNCATE`, or a
    /// `DELETE`/`UPDATE` with no `WHERE` clause.
    let isDestructive: Bool
}

/// Heuristic, keyword-based classification used by the read-only guard and the
/// destructive-statement confirmation. It is a *safety net*, not a security
/// boundary — only recognised writes are flagged, so anything unrecognised is
/// allowed through rather than risk blocking a legitimate read. Pure / testable.
nonisolated enum SQLStatementClassifier {

    static func classify(_ statement: String) -> SQLStatementInfo {
        let code = strippedUppercasedCode(statement)
        let words = code.split { !($0.isLetter || $0.isNumber || $0 == "_") }.map(String.init)
        guard let first = words.first else {
            return SQLStatementInfo(leadingKeyword: "", kind: .neutral, isDestructive: false)
        }

        let kind: SQLStatementKind
        if writeKeywords.contains(first) {
            kind = .write
        } else if readKeywords.contains(first) {
            kind = .read
        } else if neutralKeywords.contains(first) {
            kind = .neutral
        } else if first == "WITH" {
            // A CTE is a write iff it ultimately runs a data-modifying statement.
            kind = words.contains(where: dataModifyingKeywords.contains) ? .write : .read
        } else if first == "EXPLAIN" {
            // EXPLAIN ANALYZE actually executes the plan (writes included).
            kind = words.contains("ANALYZE") ? .write : .read
        } else {
            kind = .neutral
        }

        var isDestructive = (first == "DROP" || first == "TRUNCATE")
        if first == "DELETE" || first == "UPDATE" {
            isDestructive = !words.contains("WHERE")
        }

        return SQLStatementInfo(leadingKeyword: first, kind: kind, isDestructive: isDestructive)
    }

    /// Split `sql` into statements and classify each non-empty one.
    static func classifyAll(_ sql: String) -> [SQLStatementInfo] {
        SQLStatementSplitter.split(sql).map(classify)
    }

    // MARK: - Keyword tables

    private static let readKeywords: Set<String> = [
        "SELECT", "TABLE", "VALUES", "SHOW", "DESCRIBE", "DESC", "PRAGMA",
    ]
    private static let writeKeywords: Set<String> = [
        "INSERT", "UPDATE", "DELETE", "MERGE", "REPLACE", "UPSERT",
        "CREATE", "DROP", "ALTER", "TRUNCATE", "RENAME",
        "GRANT", "REVOKE", "COMMENT", "SECURITY",
        "REINDEX", "VACUUM", "CLUSTER", "COPY", "CALL", "DO",
        "REFRESH", "IMPORT", "LOAD", "ATTACH", "DETACH",
    ]
    private static let neutralKeywords: Set<String> = [
        "BEGIN", "START", "COMMIT", "ROLLBACK", "END", "ABORT",
        "SAVEPOINT", "RELEASE", "SET", "RESET", "USE", "DISCARD",
        "LISTEN", "UNLISTEN", "NOTIFY", "CHECKPOINT", "ANALYZE",
        "DEALLOCATE", "PREPARE", "EXECUTE", "FETCH", "MOVE", "CLOSE", "DECLARE",
    ]
    private static let dataModifyingKeywords: Set<String> = [
        "INSERT", "UPDATE", "DELETE", "MERGE",
    ]

    // MARK: - Stripping

    /// Returns `sql` upper-cased with comments and string/dollar-quoted literal
    /// *contents* replaced by spaces, so keyword scanning never trips over a value
    /// like `'... WHERE ...'` or a commented-out `DROP`.
    private static func strippedUppercasedCode(_ sql: String) -> String {
        var out = ""
        var inSingle = false, inLine = false, inBlock = false, inDollar = false
        var dollarTag = ""
        let chars = Array(sql)
        var i = 0

        while i < chars.count {
            let c = chars[i]
            let next: Character? = (i + 1 < chars.count) ? chars[i + 1] : nil

            if inLine {
                if c == "\n" { inLine = false; out.append(" ") }
                i += 1; continue
            }
            if inBlock {
                if c == "*" && next == "/" { inBlock = false; i += 2; out.append(" "); continue }
                i += 1; continue
            }
            if inDollar {
                if c == "$", let tag = dollarTagAt(i, in: chars), tag == dollarTag {
                    inDollar = false; dollarTag = ""
                    i += tag.count; out.append(" "); continue
                }
                i += 1; continue
            }
            if inSingle {
                if c == "'" {
                    if next == "'" { i += 2; continue }   // escaped quote
                    inSingle = false; out.append(" ")
                }
                i += 1; continue
            }

            // Not currently inside a literal/comment.
            if c == "-" && next == "-" { inLine = true; i += 1; continue }
            if c == "/" && next == "*" { inBlock = true; i += 1; continue }
            if c == "'" { inSingle = true; i += 1; continue }
            if c == "$", let tag = dollarTagAt(i, in: chars) {
                inDollar = true; dollarTag = tag; i += tag.count; continue
            }

            out.append(Character(c.uppercased()))
            i += 1
        }
        return out
    }

    /// If a `$tag$` opener starts at `i`, returns it (e.g. `"$$"`, `"$body$"`).
    private static func dollarTagAt(_ i: Int, in chars: [Character]) -> String? {
        guard chars[i] == "$" else { return nil }
        var tag = "$"
        var j = i + 1
        while j < chars.count && (chars[j].isLetter || chars[j].isNumber || chars[j] == "_") {
            tag.append(chars[j]); j += 1
        }
        guard j < chars.count && chars[j] == "$" else { return nil }
        tag.append("$")
        return tag
    }
}
