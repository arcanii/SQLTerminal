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

    var body: some View {
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
        .sheet(isPresented: $vm.isShowingConnectionSheet) {
            ConnectionSheet()
                .interactiveDismissDisabled()
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    vm.executeCurrentQuery()
                } label: {
                    Label("Execute (⌘E)", systemImage: "play.fill")
                }
                .help("Execute query (⌘E)")
                .disabled(!vm.isConnected)

                Button {
                    vm.isShowingConnectionSheet = true
                } label: {
                    Label("Reconnect", systemImage: "arrow.triangle.2.circlepath")
                }
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

            TextEditor(text: $vm.sqlText)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .autocorrectionDisabled(true)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .onAppear {
                    // Disable smart quotes and dashes globally for NSTextView
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
