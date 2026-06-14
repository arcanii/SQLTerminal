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
// HistorySnippetsView.swift
// SQLTerminal

import SwiftUI
import AppKit

/// Searchable, persistent query history and saved snippets. Clicking an item
/// loads it into the editor. Opened from the toolbar.
struct HistorySnippetsView: View {
    @EnvironmentObject var vm: TerminalViewModel
    @Environment(\.dismiss) private var dismiss

    private enum Mode: String, CaseIterable, Identifiable {
        case recent = "Recent", snippets = "Snippets"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .recent
    @State private var search = ""
    @State private var entries: [QueryHistoryEntry] = []
    @State private var snippets: [QuerySnippet] = []
    @State private var showingSaveSnippet = false
    @State private var newSnippetName = ""

    var body: some View {
        VStack(spacing: 0) {
            picker
            Divider()
            list
            Divider()
            footer
        }
        .frame(width: 540, height: 460)
        .onAppear(perform: reload)
        .alert("Save Snippet", isPresented: $showingSaveSnippet) {
            TextField("Name", text: $newSnippetName)
            Button("Save") {
                SnippetStore.save(name: newSnippetName, sql: vm.sqlText)
                newSnippetName = ""
                mode = .snippets
                reload()
            }
            Button("Cancel", role: .cancel) { newSnippetName = "" }
        } message: {
            Text("Save the current editor query as a reusable snippet.")
        }
    }

    // MARK: - Header

    private var picker: some View {
        VStack(spacing: 8) {
            Picker("", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search…", text: $search)
                    .textFieldStyle(.plain)
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
        }
        .padding(12)
    }

    // MARK: - List

    @ViewBuilder
    private var list: some View {
        switch mode {
        case .recent:
            if filteredEntries.isEmpty {
                placeholder(search.isEmpty ? "No history yet" : "No matches")
            } else {
                List(filteredEntries) { entry in
                    row(sql: entry.sql, subtitle: subtitle(for: entry))
                        .contentShape(Rectangle())
                        .onTapGesture { insert(entry.sql) }
                        .contextMenu {
                            Button("Insert") { insert(entry.sql) }
                            Button("Copy") { copy(entry.sql) }
                        }
                }
            }
        case .snippets:
            if filteredSnippets.isEmpty {
                placeholder(search.isEmpty ? "No saved snippets" : "No matches")
            } else {
                List(filteredSnippets) { snippet in
                    row(sql: snippet.sql, subtitle: snippet.name, subtitleIsName: true)
                        .contentShape(Rectangle())
                        .onTapGesture { insert(snippet.sql) }
                        .contextMenu {
                            Button("Insert") { insert(snippet.sql) }
                            Button("Copy") { copy(snippet.sql) }
                            Divider()
                            Button("Delete", role: .destructive) {
                                SnippetStore.remove(snippet); reload()
                            }
                        }
                }
            }
        }
    }

    private func row(sql: String, subtitle: String, subtitleIsName: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if subtitleIsName {
                Text(subtitle).font(.caption).bold()
            }
            Text(sql)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(2)
                .foregroundStyle(subtitleIsName ? .secondary : .primary)
            if !subtitleIsName {
                Text(subtitle).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private func placeholder(_ text: String) -> some View {
        VStack { Spacer(); Text(text).foregroundStyle(.secondary); Spacer() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button {
                newSnippetName = ""
                showingSaveSnippet = true
            } label: {
                Label("Save Current as Snippet…", systemImage: "plus")
            }
            .disabled(vm.sqlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if mode == .recent, !entries.isEmpty {
                Button("Clear History", role: .destructive) {
                    QueryHistoryStore.clear(); reload()
                }
            }

            Spacer()
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(12)
    }

    // MARK: - Data

    private var filteredEntries: [QueryHistoryEntry] {
        guard !search.isEmpty else { return entries }
        return entries.filter { $0.sql.localizedCaseInsensitiveContains(search) }
    }

    private var filteredSnippets: [QuerySnippet] {
        guard !search.isEmpty else { return snippets }
        return snippets.filter {
            $0.name.localizedCaseInsensitiveContains(search) || $0.sql.localizedCaseInsensitiveContains(search)
        }
    }

    private func subtitle(for entry: QueryHistoryEntry) -> String {
        let when = entry.lastRun.formatted(.relative(presentation: .named))
        return entry.runCount > 1 ? "\(when) · run \(entry.runCount)×" : when
    }

    private func reload() {
        entries = QueryHistoryStore.load()
        snippets = SnippetStore.load()
    }

    private func insert(_ sql: String) {
        vm.sqlText = sql
        dismiss()
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
