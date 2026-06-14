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
// HelpView.swift
// SQLTerminal

import SwiftUI
import AppKit

/// A concise, offline reference for SQLTerminal — keyboard shortcuts, features,
/// and where to find things. Opened from Help ▸ SQLTerminal Help (⌘?).
struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                section("Keyboard Shortcuts") {
                    shortcut("⌘E", "Run the whole editor")
                    shortcut("⌘↩", "Run the selection, or the statement under the cursor")
                    shortcut("⌘.", "Cancel the running query")
                    shortcut("⌘↑ / ⌘↓", "Previous / next command from history")
                    shortcut("⌘N", "New window (independent session)")
                    shortcut("⌘W", "Close window")
                    shortcut("⌘?", "Show this help")
                }

                section("Editor") {
                    bullet("Write SQL in the bottom pane; results appear above.")
                    bullet("Keywords, strings, comments, and numbers are syntax-highlighted.")
                    bullet("Run multiple statements at once, separated by `;` (PL/pgSQL `$$` blocks are handled).")
                    bullet("**Read-only mode** (toolbar) blocks writes; destructive statements (DROP / TRUNCATE / WHERE-less DELETE/UPDATE) ask for confirmation.")
                    bullet("**Transactions** — Begin / Commit / Rollback from the toolbar menu.")
                }

                section("Connections") {
                    bullet("Connect to **SQLite** files or **PostgreSQL** servers.")
                    bullet("PostgreSQL **SSL/TLS**: Off / Prefer / Require — a green lock in the status bar means the connection is encrypted.")
                    bullet("Recent connections, saved profiles, and Keychain passwords speed up reconnecting.")
                    bullet("Click the connection in the status bar for details. `.connect <db>` / `.use <db>` switch databases.")
                }

                section("Browsing & Results") {
                    bullet("**Schema sidebar** (toolbar) lists tables and columns — click a table to drop a `SELECT` in the editor.")
                    bullet("**History & Snippets** (toolbar) — search past queries or saved snippets and click to reload one.")
                    bullet("Click a result header to **sort**; right-click a cell → **View value…** to expand long text or JSON.")
                    bullet("Copy results as **TSV** or **CSV**, or right-click any row/cell to copy.")
                }

                section("Dot-commands") {
                    Text("Type **.help** in the editor for the full list of dot-commands (e.g. `.tables`, `.schema <table>`, `.count <table>`, `.dbinfo`).")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                footer
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 480, height: 580)
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(spacing: 12) {
            Image("AboutLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text("SQLTerminal Help")
                    .font(.title2).bold()
                Text("A quick reference. For the full README, see GitHub.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Documentation on GitHub") {
                if let url = URL(string: "https://github.com/arcanii/SQLTerminal") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.link)
            Spacer()
        }
        .font(.caption)
    }

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            content()
            Divider()
        }
    }

    private func shortcut(_ keys: String, _ description: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(keys)
                .font(.system(.body, design: .monospaced))
                .frame(width: 90, alignment: .leading)
            Text(description)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    private func bullet(_ markdown: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•").foregroundStyle(.secondary)
            Text(.init(markdown))   // render **bold** / `code`
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
