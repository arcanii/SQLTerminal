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
// SQLStatementSplitter.swift
// SQLTerminal / SQLCore

import Foundation

/// Splits a SQL string into individual statements at top-level semicolons,
/// correctly ignoring semicolons inside single-quoted strings, line/block
/// comments, and `$tag$ … $tag$` dollar-quoted blocks (PL/pgSQL bodies).
///
/// This is the single source of truth for statement boundaries: `PostgresProvider`
/// uses it to execute multi-statement input, and the editor uses it to find the
/// statement under the cursor and to classify statements for the safety guards.
/// It is pure (`Foundation` only) so it can be unit-tested in the `SQLCore`
/// package without spinning up the app.
nonisolated enum SQLStatementSplitter {

    /// A statement and the half-open character-offset range `[start, end)` it
    /// occupies in the original input (offsets index `Array(sql)`).
    struct Segment {
        let text: String          // trimmed; may be empty (whitespace/comment only)
        let start: Int
        let end: Int
    }

    /// The trimmed, non-empty statements, in order (each keeps its trailing `;`).
    static func split(_ sql: String) -> [String] {
        segments(sql).map(\.text).filter { !$0.isEmpty }
    }

    /// The trimmed statement whose range contains `cursorOffset`, or `nil` if that
    /// position falls only in whitespace/comments between statements. Used for
    /// "run the statement under the cursor".
    static func statement(atOffset cursorOffset: Int, in sql: String) -> String? {
        let segs = segments(sql)
        guard !segs.isEmpty else { return nil }

        // Prefer the segment whose range strictly contains the cursor; on an exact
        // boundary, favour the segment ending there (so a cursor just past a `;`
        // still targets the statement you just finished typing).
        let hit = segs.first { cursorOffset >= $0.start && cursorOffset < $0.end }
            ?? segs.last { cursorOffset >= $0.start && cursorOffset <= $0.end }
            ?? segs.last
        guard let segment = hit, !segment.text.isEmpty else { return nil }
        return segment.text
    }

    // MARK: - Core scanner

    /// Walks the input once, emitting a `Segment` per top-level `;`-delimited run
    /// (plus a trailing run). Quote/comment/dollar-quote state is tracked so only
    /// genuine statement-terminating semicolons split.
    static func segments(_ sql: String) -> [Segment] {
        var segments: [Segment] = []
        var current = ""
        var segmentStart = 0
        var inDollarQuote = false
        var dollarTag = ""
        var inSingleQuote = false
        var inLineComment = false
        var inBlockComment = false
        let chars = Array(sql)
        var i = 0

        func emit(end: Int) {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            segments.append(Segment(text: trimmed, start: segmentStart, end: end))
            current = ""
            segmentStart = end
        }

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
                var tag = "$"
                var j = i + 1
                while j < chars.count && (chars[j].isLetter || chars[j].isNumber || chars[j] == "_") {
                    tag.append(chars[j])
                    j += 1
                }
                if j < chars.count && chars[j] == "$" {
                    tag.append("$")
                    if inDollarQuote && tag == dollarTag {
                        current.append(tag)
                        inDollarQuote = false
                        dollarTag = ""
                        i = j + 1
                        continue
                    } else if !inDollarQuote {
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

            // Single quotes (with '' escape)
            if c == "'" && !inDollarQuote {
                inSingleQuote.toggle()
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
                emit(end: i + 1)
                i += 1
                continue
            }

            current.append(c)
            i += 1
        }

        // Trailing run (no terminating semicolon)
        emit(end: chars.count)
        return segments
    }
}
