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
// TerminalView.swift
// SQLTerminal

import SwiftUI
import Combine
import AppKit

struct TerminalView: View {
    @EnvironmentObject var vm: TerminalViewModel
    @State private var editorHeight: CGFloat = 150
    /// The editor's current selection/caret, used to run just the selected SQL
    /// or the statement under the cursor (UTF-16 range from the editor).
    @State private var selectedRange = NSRange(location: 0, length: 0)
    /// Whether the schema sidebar is shown.
    @State private var showSidebar = true
    /// Whether the history & snippets sheet is shown.
    @State private var showHistory = false

    var body: some View {
        HStack(spacing: 0) {
            if showSidebar {
                SchemaSidebarView()
                    .frame(width: 240)
                Divider()
            }
            terminalPane
        }
        .sheet(isPresented: $vm.isShowingConnectionSheet) {
            ConnectionSheet()
                .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showHistory) {
            HistorySnippetsView()
                .environmentObject(vm)
        }
        .confirmationDialog(
            "Run destructive statement?",
            isPresented: Binding(
                get: { vm.pendingConfirmation != nil },
                set: { if !$0 { vm.cancelPendingExecution() } }
            ),
            presenting: vm.pendingConfirmation
        ) { _ in
            Button("Run anyway", role: .destructive) { vm.confirmPendingExecution() }
            Button("Cancel", role: .cancel) { vm.cancelPendingExecution() }
        } message: { pending in
            Text(pending.message)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    showSidebar.toggle()
                } label: {
                    Label("Toggle Sidebar", systemImage: "sidebar.left")
                }
                .help("Show or hide the schema sidebar")
            }
            ToolbarItem(placement: .navigation) {
                Button {
                    showHistory = true
                } label: {
                    Label("History & Snippets", systemImage: "clock.arrow.circlepath")
                }
                .help("Searchable query history and saved snippets")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Toggle(isOn: $vm.isReadOnly) {
                    Label("Read-only", systemImage: "pencil.slash")
                }
                .toggleStyle(.button)
                .help(vm.isReadOnly
                      ? "Read-only mode is ON — write/DDL statements are blocked"
                      : "Read-only mode is OFF — click to block writes")

                if vm.isRunning {
                    ProgressView()
                        .controlSize(.small)
                    Button {
                        vm.cancelRunningQuery()
                    } label: {
                        Label("Cancel", systemImage: "stop.fill")
                    }
                    .help("Cancel running query (⌘.)")
                    .keyboardShortcut(".", modifiers: .command)
                } else {
                    if vm.isConnecting {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Button {
                        vm.executeCurrentQuery()
                    } label: {
                        Label("Execute (⌘E)", systemImage: "play.fill")
                    }
                    .help("Execute the whole editor (⌘E)")
                    .disabled(!vm.isConnected || vm.isConnecting)

                    Button {
                        vm.executeSnippet(snippetToRun())
                    } label: {
                        Label("Run Selection (⌘↩)", systemImage: "play.rectangle")
                    }
                    .help("Run the selected SQL, or the statement under the cursor (⌘↩)")
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!vm.isConnected || vm.isConnecting)
                }

                Menu {
                    Button {
                        vm.beginTransaction()
                    } label: {
                        Label("Begin", systemImage: "play.circle")
                    }
                    .disabled(vm.inTransaction)

                    Button {
                        vm.commitTransaction()
                    } label: {
                        Label("Commit", systemImage: "checkmark.circle")
                    }
                    .disabled(!vm.inTransaction)

                    Button(role: .destructive) {
                        vm.rollbackTransaction()
                    } label: {
                        Label("Rollback", systemImage: "arrow.uturn.backward.circle")
                    }
                    .disabled(!vm.inTransaction)
                } label: {
                    Label("Transaction", systemImage: "arrow.triangle.branch")
                }
                .help(vm.inTransaction ? "A transaction is open" : "Begin / Commit / Rollback")
                .disabled(!vm.isConnected || vm.isRunning || vm.isConnecting)

                Button {
                    vm.isShowingConnectionSheet = true
                } label: {
                    Label("Reconnect", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(vm.isRunning || vm.isConnecting)
            }
        }
    }

    // MARK: - Terminal pane (history + editor + status bar)

    private var terminalPane: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {

                // ── Top: History / Output area ──
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(vm.history.enumerated()), id: \.offset) { index, entry in
                                historyRow(entry)
                                    .id(index)
                            }
                        }
                        .padding()
                        // Let the user click-drag to select text anywhere in the
                        // output pane. Applied here, it propagates through the
                        // environment to every Text below — history rows and the
                        // result-table cells alike.
                        .textSelection(.enabled)
                    }
                    .onChange(of: vm.history.count) { _, _ in
                        withAnimation {
                            proxy.scrollTo(vm.history.count - 1, anchor: .bottom)
                        }
                    }
                }
                .background(Color(nsColor: .textBackgroundColor))

                // ── Draggable divider ──
                DragDivider(editorHeight: $editorHeight, totalHeight: geo.size.height)

                // ── Bottom: SQL Input area ──
                sqlInputArea
                    .frame(height: editorHeight)

                Divider()

                // ── Status bar ──
                StatusBarView()
            }
        }
    }

    // MARK: - SQL Editor

    private var sqlInputArea: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("SQL")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("⌘E execute  ⌘↑↓ history")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)

            SQLEditorView(text: $vm.sqlText, selectedRange: $selectedRange)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .onAppear {
                    // SQLEditorView disables smart substitution on its own text
                    // view; also disable it globally so the connection sheet's
                    // fields don't mangle quotes/dashes either.
                    UserDefaults.standard.set(false, forKey: "NSAutomaticQuoteSubstitutionEnabled")
                    UserDefaults.standard.set(false, forKey: "NSAutomaticDashSubstitutionEnabled")
                    UserDefaults.standard.set(false, forKey: "NSAutomaticTextReplacementEnabled")
                    UserDefaults.standard.set(false, forKey: "NSAutomaticSpellingCorrectionEnabled")
                }

        }
    }

    // MARK: - History rendering

    @ViewBuilder
    private func historyRow(_ entry: HistoryEntry) -> some View {
        switch entry {
        case .input(let sql):
            HStack(alignment: .top, spacing: 6) {
                Text("▶")
                    .foregroundStyle(.blue)
                    .font(.system(.body, design: .monospaced))
                Text(sql)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.primary)
            }
            .contextMenu {
                Button("Copy SQL") {
                    copyToClipboard(sql)
                }
            }

        case .result(let result):
            ResultsTableView(result: result)

        case .error(let msg):
            HStack(alignment: .top, spacing: 6) {
                Text("✗")
                    .foregroundStyle(.red)
                    .font(.system(.body, design: .monospaced))
                Text(msg)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.red)
            }
            .contextMenu {
                Button("Copy Error") {
                    copyToClipboard(msg)
                }
            }

        case .system(let msg):
            Text(msg)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .italic()
                .contextMenu {
                    Button("Copy") {
                        copyToClipboard(msg)
                    }
                }
        }
    }

    // MARK: - Run selection / statement-at-cursor

    /// The SQL to run for ⌘↩: the selected text, or the statement under the caret
    /// when nothing is selected. Returns `nil` to fall back to the whole editor.
    private func snippetToRun() -> String? {
        let ns = vm.sqlText as NSString
        let bounds = NSRange(location: 0, length: ns.length)

        // A non-empty selection runs verbatim.
        let selected = NSIntersectionRange(selectedRange, bounds)
        if selected.length > 0 {
            return ns.substring(with: selected)
        }

        // Otherwise, the statement under the caret.
        let caret = min(selectedRange.location, ns.length)
        let offset = characterOffset(utf16: caret, in: vm.sqlText)
        return SQLStatementSplitter.statement(atOffset: offset, in: vm.sqlText)
    }

    /// Convert a UTF-16 offset (from the editor) to a Character offset (what the
    /// splitter counts in). Identical for ASCII; correct for everything else.
    private func characterOffset(utf16 offset: Int, in string: String) -> Int {
        guard let u16 = string.utf16.index(string.utf16.startIndex, offsetBy: offset,
                                            limitedBy: string.utf16.endIndex),
              let idx = u16.samePosition(in: string) else { return offset }
        return string.distance(from: string.startIndex, to: idx)
    }

    // MARK: - Clipboard

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

// MARK: - Draggable Divider

struct DragDivider: View {
    @Binding var editorHeight: CGFloat
    let totalHeight: CGFloat

    private let minEditor: CGFloat = 80
    private let minResults: CGFloat = 100
    private let statusBarHeight: CGFloat = 30

    var body: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .frame(height: 6)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gray.opacity(0.5))
                    .frame(width: 40, height: 3)
            )
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let maxEditor = totalHeight - minResults - statusBarHeight
                        let newHeight = editorHeight - value.translation.height
                        editorHeight = min(max(newHeight, minEditor), maxEditor)
                    }
            )
    }
}
