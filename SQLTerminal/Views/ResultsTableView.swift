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
                        // Header
                        HStack(spacing: 0) {
                            ForEach(result.columns, id: \.self) { col in
                                Text(col)
                                    .font(.system(.caption, design: .monospaced))
                                    .bold()
                                    .frame(minWidth: 120, alignment: .leading)
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 8)
                                    .background(Color.accentColor.opacity(0.12))
                            }
                        }
                        .contextMenu {
                            Button("Copy Header Row") {
                                copyToClipboard(result.columns.joined(separator: "\t"))
                            }
                        }

                        Divider()

                        // Rows
                        ForEach(Array(result.rows.enumerated()), id: \.offset) { rowIdx, row in
                            HStack(spacing: 0) {
                                ForEach(Array(row.enumerated()), id: \.offset) { _, value in
                                    Text(value)
                                        .font(.system(.caption, design: .monospaced))
                                        .frame(minWidth: 120, alignment: .leading)
                                        .padding(.vertical, 3)
                                        .padding(.horizontal, 8)
                                }
                            }
                            .background(rowIdx % 2 == 0 ? Color.clear : Color.gray.opacity(0.06))
                            .contextMenu {
                                Button("Copy Row") {
                                    copyToClipboard(row.joined(separator: "\t"))
                                }
                                ForEach(Array(zip(result.columns, row).enumerated()), id: \.offset) { _, pair in
                                    Button("Copy \(pair.0): \(pair.1.prefix(30))") {
                                        copyToClipboard(pair.1)
                                    }
                                }
                            }
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
        for row in result.rows {
            lines.append(row.joined(separator: "\t"))
        }
        copyToClipboard(lines.joined(separator: "\n"))
    }

    private func copyAsCSV() {
        var lines: [String] = []
        lines.append(result.columns.map { csvEscape($0) }.joined(separator: ","))
        for row in result.rows {
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
