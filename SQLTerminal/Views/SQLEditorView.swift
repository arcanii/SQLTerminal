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
// SQLEditorView.swift
// SQLTerminal

import SwiftUI
import AppKit

/// A syntax-highlighting SQL editor. SwiftUI's `TextEditor` can only render a
/// plain `String`, so this wraps an `NSTextView`, keeping `text` and
/// `selectedRange` in sync with SwiftUI and re-colouring on each edit.
struct SQLEditorView: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange

    static let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true

        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = Self.font
        textView.textColor = .textColor
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.string = text
        if let storage = textView.textStorage {
            SQLSyntaxHighlighter.highlight(storage, font: Self.font)
        }
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        // Only react to external text changes (history insert, clear, ⌘↑/↓ nav);
        // user edits flow out via the delegate, not back through here.
        if textView.string != text {
            context.coordinator.isProgrammaticChange = true
            let previous = textView.selectedRange()
            textView.string = text
            if let storage = textView.textStorage {
                SQLSyntaxHighlighter.highlight(storage, font: Self.font)
            }
            let length = (text as NSString).length
            textView.setSelectedRange(NSRange(location: min(previous.location, length), length: 0))
            context.coordinator.isProgrammaticChange = false
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: SQLEditorView
        weak var textView: NSTextView?
        var isProgrammaticChange = false

        init(_ parent: SQLEditorView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            // Don't recolour mid-IME-composition (would drop the marked text).
            if !textView.hasMarkedText(), let storage = textView.textStorage {
                SQLSyntaxHighlighter.highlight(storage, font: SQLEditorView.font)
            }
            parent.selectedRange = textView.selectedRange()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isProgrammaticChange,
                  let textView = notification.object as? NSTextView else { return }
            parent.selectedRange = textView.selectedRange()
        }
    }
}

// MARK: - Highlighter

/// Applies SQL colours to an `NSTextStorage`: keywords, numbers, then string and
/// comment spans last so they win over keyword/number colouring inside them.
/// Boundary detection comes from the unit-tested `SQLLiteralScanner`.
enum SQLSyntaxHighlighter {

    private static let keywordColor = NSColor.systemPink
    private static let stringColor  = NSColor.systemRed
    private static let commentColor = NSColor.systemGreen
    private static let numberColor  = NSColor.systemPurple

    static func highlight(_ storage: NSTextStorage, font: NSFont) {
        let full = NSRange(location: 0, length: (storage.string as NSString).length)

        storage.beginEditing()
        defer { storage.endEditing() }

        storage.setAttributes([.font: font, .foregroundColor: NSColor.textColor], range: full)

        for match in numberRegex.matches(in: storage.string, range: full) {
            add(numberColor, match.range, full, storage)
        }
        for match in keywordRegex.matches(in: storage.string, range: full) {
            add(keywordColor, match.range, full, storage)
        }
        for literal in SQLLiteralScanner.literalAndCommentRanges(in: storage.string) {
            add(literal.isComment ? commentColor : stringColor, literal.range, full, storage)
        }
    }

    /// Add a colour, clamped to `full` so a stray range can never crash.
    private static func add(_ color: NSColor, _ range: NSRange, _ full: NSRange, _ storage: NSTextStorage) {
        let safe = NSIntersectionRange(range, full)
        if safe.length > 0 {
            storage.addAttribute(.foregroundColor, value: color, range: safe)
        }
    }

    private static let numberRegex = try! NSRegularExpression(pattern: #"\b\d+(?:\.\d+)?\b"#)

    private static let keywordRegex: NSRegularExpression = {
        let pattern = #"\b(?:"# + keywords.joined(separator: "|") + #")\b"#
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()

    private static let keywords: [String] = [
        "ABORT", "ADD", "ALL", "ALTER", "AND", "AS", "ASC", "ATTACH", "AUTOINCREMENT",
        "BEGIN", "BETWEEN", "BY", "CALL", "CASCADE", "CASE", "CAST", "CHECK", "CLUSTER",
        "COLLATE", "COLUMN", "COMMENT", "COMMIT", "CONSTRAINT", "COPY", "CREATE",
        "CROSS", "CURRENT", "DATABASE", "DEFAULT", "DEFERRABLE", "DELETE", "DESC",
        "DETACH", "DISTINCT", "DO", "DROP", "ELSE", "END", "ESCAPE", "EXCEPT", "EXISTS",
        "EXPLAIN", "FALSE", "FOREIGN", "FROM", "FULL", "GRANT", "GROUP", "HAVING", "IF",
        "ILIKE", "IN", "INDEX", "INNER", "INSERT", "INTO", "IS", "JOIN", "KEY", "LEFT",
        "LIKE", "LIMIT", "MERGE", "NATURAL", "NOT", "NULL", "OFFSET", "ON", "OR", "ORDER",
        "OUTER", "PRAGMA", "PRIMARY", "REFERENCES", "REINDEX", "RENAME", "REPLACE",
        "RETURNING", "REVOKE", "RIGHT", "ROLLBACK", "SAVEPOINT", "SELECT", "SET", "SHOW",
        "TABLE", "TEMP", "TEMPORARY", "THEN", "TRIGGER", "TRUE", "TRUNCATE",
        "UNION", "UNIQUE", "UPDATE", "USING", "VACUUM", "VALUES", "VIEW", "WHEN", "WHERE",
        "WITH",
    ]
}
