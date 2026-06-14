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
// ResultsTableView.swift
// SQLTerminal

import SwiftUI
import Combine
import AppKit

struct ResultsTableView: View {
    let result: QueryResult

    /// Index of the column the rows are sorted by, and the direction.
    @State private var sortColumn: Int?
    @State private var sortAscending = true
    /// The cell currently shown in the detail sheet, if any.
    @State private var cellDetail: CellDetail?

    private let columnWidth: CGFloat = 120

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {

            if result.statementType == .query && !result.columns.isEmpty {

                // Copy buttons
                HStack(spacing: 8) {
                    Spacer()
                    Button {
                        copyAsTab()
                    } label: {
                        Label("Copy as TSV", systemImage: "doc.on.doc")
                            .font(.caption2)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)

                    Button {
                        copyAsCSV()
                    } label: {
                        Label("Copy as CSV", systemImage: "tablecells")
                            .font(.caption2)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }

                // Table with both scrollbars
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        // Header — click to sort
                        HStack(spacing: 0) {
                            ForEach(Array(result.columns.enumerated()), id: \.offset) { idx, col in
                                Button {
                                    toggleSort(idx)
                                } label: {
                                    HStack(spacing: 3) {
                                        Text(col)
                                            .font(.system(.caption, design: .monospaced))
                                            .bold()
                                        if sortColumn == idx {
                                            Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                                                .font(.system(size: 8, weight: .bold))
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .frame(minWidth: columnWidth, alignment: .leading)
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 8)
                                    .background(Color.accentColor.opacity(0.12))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help("Sort by \(col)")
                            }
                        }

                        Divider()

                        // Rows
                        ForEach(Array(displayRows.enumerated()), id: \.offset) { rowIdx, row in
                            HStack(spacing: 0) {
                                ForEach(Array(row.enumerated()), id: \.offset) { colIdx, value in
                                    Text(value)
                                        .font(.system(.caption, design: .monospaced))
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .frame(minWidth: columnWidth, alignment: .leading)
                                        .padding(.vertical, 3)
                                        .padding(.horizontal, 8)
                                        .contextMenu {
                                            Button("View value…") {
                                                cellDetail = CellDetail(column: columnName(colIdx), value: value)
                                            }
                                            Button("Copy value") { copyToClipboard(value) }
                                            Button("Copy row") { copyToClipboard(row.joined(separator: "\t")) }
                                        }
                                }
                            }
                            .background(rowIdx % 2 == 0 ? Color.clear : Color.gray.opacity(0.06))
                        }
                    }
                }
                .scrollIndicators(.visible)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
            }

            // Summary line
            HStack(spacing: 12) {
                if result.statementType == .query {
                    Text("\(result.rows.count) row(s) returned")
                } else {
                    Text("\(result.rowsAffected) row(s) affected")
                }
                Text("•")
                Text(String(format: "%.3f s", result.executionTime))
            }
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(.secondary)
        }
        .sheet(item: $cellDetail) { detail in
            CellDetailView(detail: detail)
        }
    }

    // MARK: - Sorting

    /// Rows in the current sort order (or original order when unsorted).
    private var displayRows: [[String]] {
        guard let col = sortColumn else { return result.rows }
        return result.rows.enumerated().sorted { lhs, rhs in
            let cmp = Self.smartCompare(value(lhs.element, col), value(rhs.element, col))
            if cmp == .orderedSame { return lhs.offset < rhs.offset }   // stable
            return sortAscending ? (cmp == .orderedAscending) : (cmp == .orderedDescending)
        }.map(\.element)
    }

    private func toggleSort(_ col: Int) {
        if sortColumn == col {
            sortAscending.toggle()
        } else {
            sortColumn = col
            sortAscending = true
        }
    }

    private func value(_ row: [String], _ col: Int) -> String {
        row.indices.contains(col) ? row[col] : ""
    }

    private func columnName(_ col: Int) -> String {
        result.columns.indices.contains(col) ? result.columns[col] : "col\(col)"
    }

    /// Compare numerically when both values are numbers, naturally otherwise;
    /// NULLs sort after everything else.
    static func smartCompare(_ a: String, _ b: String) -> ComparisonResult {
        if a == b { return .orderedSame }
        if a == "NULL" { return .orderedDescending }
        if b == "NULL" { return .orderedAscending }
        if let da = Double(a), let db = Double(b) {
            return da == db ? .orderedSame : (da < db ? .orderedAscending : .orderedDescending)
        }
        return a.localizedStandardCompare(b)
    }

    // MARK: - Copy helpers

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func copyAsTab() {
        var lines: [String] = []
        lines.append(result.columns.joined(separator: "\t"))
        for row in displayRows {
            lines.append(row.joined(separator: "\t"))
        }
        copyToClipboard(lines.joined(separator: "\n"))
    }

    private func copyAsCSV() {
        var lines: [String] = []
        lines.append(result.columns.map { csvEscape($0) }.joined(separator: ","))
        for row in displayRows {
            lines.append(row.map { csvEscape($0) }.joined(separator: ","))
        }
        copyToClipboard(lines.joined(separator: "\n"))
    }

    private func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}

// MARK: - Cell detail

/// A single cell's value, shown in the detail sheet.
struct CellDetail: Identifiable {
    let id = UUID()
    let column: String
    let value: String
}

/// Expands a single cell value — handy for long text or JSON. Offers a
/// pretty-print toggle when the value is valid JSON.
private struct CellDetailView: View {
    let detail: CellDetail
    @Environment(\.dismiss) private var dismiss
    @State private var prettyJSON = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(detail.column)
                    .font(.headline)
                Spacer()
                if prettyValue != nil {
                    Toggle("Format JSON", isOn: $prettyJSON)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }

            ScrollView {
                Text(shownValue)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))

            HStack {
                Text("\(detail.value.count) characters")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Copy") { copy(shownValue) }
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(width: 540, height: 440)
    }

    private var shownValue: String {
        (prettyJSON ? prettyValue : nil) ?? detail.value
    }

    /// The value pretty-printed, if it is valid JSON; otherwise nil.
    private var prettyValue: String? {
        guard let data = detail.value.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj,
                                                       options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: pretty, encoding: .utf8)
        else { return nil }
        return string
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
