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
// SchemaSidebarView.swift
// SQLTerminal

import SwiftUI
import AppKit

/// A collapsible object browser: the current connection's tables (public schema
/// for Postgres), each expandable to its columns. Clicking a table drops a
/// starter SELECT into the editor; the context menu can preview it. All metadata
/// is fetched off-main via the view model.
struct SchemaSidebarView: View {
    @EnvironmentObject var vm: TerminalViewModel

    @State private var tables: [String] = []
    @State private var columns: [String: [SchemaColumn]] = [:]
    @State private var expanded: Set<String> = []
    @State private var isLoading = false
    @State private var hasLoaded = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .controlBackgroundColor))
        .task(id: vm.connectionInfo) { await reload() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Text("TABLES")
                .font(.caption2).bold()
                .foregroundStyle(.secondary)
            if !tables.isEmpty {
                Text("\(tables.count)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button {
                Task { await reload() }
            } label: {
                if isLoading {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .disabled(!vm.isConnected || isLoading)
            .help("Refresh")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if !vm.isConnected {
            placeholder("Not connected")
        } else if isLoading && !hasLoaded {
            placeholder("Loading…")
        } else if tables.isEmpty {
            placeholder("No tables")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(tables, id: \.self) { table in
                        tableRow(table)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func placeholder(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text).font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Rows

    @ViewBuilder
    private func tableRow(_ table: String) -> some View {
        let isOpen = expanded.contains(table)

        HStack(spacing: 4) {
            Button {
                toggleExpand(table)
            } label: {
                Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
            }
            .buttonStyle(.borderless)

            Image(systemName: "tablecells")
                .font(.caption)
                .foregroundStyle(.blue)
            Text(table)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture { vm.insertSelectStatement(forTable: table) }
        .help("Click to put a SELECT in the editor")
        .contextMenu {
            Button("Preview 100 rows") { vm.previewTable(table) }
            Button("Insert SELECT") { vm.insertSelectStatement(forTable: table) }
            Button("Copy name") { copyToClipboard(table) }
        }

        if isOpen {
            ForEach(columns[table] ?? []) { column in
                HStack(spacing: 4) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 4))
                        .foregroundStyle(.tertiary)
                    Text(column.name)
                        .font(.system(.caption2, design: .monospaced))
                    Text(column.type)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.leading, 32)
                .padding(.trailing, 10)
                .padding(.vertical, 1)
            }
            if columns[table] == nil {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    Text("Loading…").font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.leading, 32)
                .padding(.vertical, 1)
            } else if columns[table]?.isEmpty == true {
                Text("No columns")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .padding(.leading, 32).padding(.vertical, 1)
            }
        }
    }

    // MARK: - Loading

    private func reload() async {
        guard vm.isConnected else {
            tables = []; columns = [:]; expanded = []; hasLoaded = false
            return
        }
        isLoading = true
        let fetched = await vm.fetchTableNames()
        tables = fetched
        columns = [:]
        expanded = []
        isLoading = false
        hasLoaded = true
    }

    private func toggleExpand(_ table: String) {
        if expanded.contains(table) {
            expanded.remove(table)
        } else {
            expanded.insert(table)
            if columns[table] == nil {
                Task {
                    let cols = await vm.fetchColumns(forTable: table)
                    columns[table] = cols
                }
            }
        }
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
