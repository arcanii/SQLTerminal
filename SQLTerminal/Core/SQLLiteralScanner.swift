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
// SQLLiteralScanner.swift
// SQLTerminal / SQLCore

import Foundation

/// A single-quoted string / dollar-quoted block, or a comment, with its UTF-16
/// range in the source (so it maps directly onto an `NSTextStorage`).
nonisolated struct SQLLiteralRange: Equatable {
    let range: NSRange
    let isComment: Bool   // true = -- or /* */ comment; false = '…' or $tag$…$tag$
}

/// Finds the string-literal and comment spans in SQL, honouring `''` escapes and
/// dollar-quoting, and the rule that a `--` inside a string isn't a comment (and
/// a `'` inside a comment isn't a string). This is the boundary logic the editor
/// highlighter relies on; it is `Foundation`-only and unit-tested in `SQLCore`.
nonisolated enum SQLLiteralScanner {

    static func literalAndCommentRanges(in text: String) -> [SQLLiteralRange] {
        let s = text as NSString
        let n = s.length
        var ranges: [SQLLiteralRange] = []
        var i = 0

        while i < n {
            let c = s.character(at: i)

            // Line comment: -- … to end of line
            if c == 0x2D, i + 1 < n, s.character(at: i + 1) == 0x2D {
                let start = i
                i += 2
                while i < n, s.character(at: i) != 0x0A { i += 1 }
                ranges.append(.init(range: NSRange(location: start, length: i - start), isComment: true))
                continue
            }

            // Block comment: /* … */
            if c == 0x2F, i + 1 < n, s.character(at: i + 1) == 0x2A {
                let start = i
                i += 2
                while i + 1 < n, !(s.character(at: i) == 0x2A && s.character(at: i + 1) == 0x2F) { i += 1 }
                i = min(i + 2, n)
                ranges.append(.init(range: NSRange(location: start, length: i - start), isComment: true))
                continue
            }

            // Single-quoted string with '' escape
            if c == 0x27 {
                let start = i
                i += 1
                while i < n {
                    if s.character(at: i) == 0x27 {
                        if i + 1 < n, s.character(at: i + 1) == 0x27 { i += 2; continue }   // escaped quote
                        i += 1
                        break
                    }
                    i += 1
                }
                ranges.append(.init(range: NSRange(location: start, length: i - start), isComment: false))
                continue
            }

            // Dollar-quoted block: $tag$ … $tag$
            if c == 0x24, let tag = dollarTag(s, at: i) {
                let start = i
                i += tag.length
                while i < n {
                    if s.character(at: i) == 0x24, let close = dollarTag(s, at: i), close.isEqual(to: tag as String) {
                        i += close.length
                        break
                    }
                    i += 1
                }
                ranges.append(.init(range: NSRange(location: start, length: i - start), isComment: false))
                continue
            }

            i += 1
        }
        return ranges
    }

    /// The `$tag$` opener starting at `i` (e.g. `"$$"`, `"$body$"`), or nil.
    private static func dollarTag(_ s: NSString, at i: Int) -> NSString? {
        let n = s.length
        guard i < n, s.character(at: i) == 0x24 else { return nil }
        var j = i + 1
        while j < n {
            let ch = s.character(at: j)
            let isWord = (ch >= 0x41 && ch <= 0x5A) || (ch >= 0x61 && ch <= 0x7A)
                || (ch >= 0x30 && ch <= 0x39) || ch == 0x5F
            if isWord { j += 1 } else { break }
        }
        guard j < n, s.character(at: j) == 0x24 else { return nil }
        return s.substring(with: NSRange(location: i, length: j - i + 1)) as NSString
    }
}
