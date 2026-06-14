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
// ConnectionDetailsView.swift
// SQLTerminal

import SwiftUI

/// The popover shown when the status-bar connection indicator (or its lock) is
/// clicked — a Safari-style "what am I connected to, and is it encrypted?" panel.
struct ConnectionDetailsView: View {
    let connection: DatabaseConnection?
    let isSSLActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider()
            if rows.isEmpty {
                Text("Not connected to any database.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(rows, id: \.label) { row in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(row.label)
                                .foregroundStyle(.secondary)
                                .frame(width: 78, alignment: .leading)
                            Text(row.value)
                                .textSelection(.enabled)
                        }
                    }
                }
                .font(.system(.caption, design: .monospaced))
            }
        }
        .padding(14)
        .frame(minWidth: 260, alignment: .leading)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: headerIcon)
                .foregroundStyle(isSSLActive ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
            Text(headerText)
                .font(.headline)
        }
    }

    private var headerIcon: String {
        guard let connection else { return "bolt.horizontal.circle" }
        switch connection.engine {
        case .sqlite:   return "internaldrive"
        case .postgres: return isSSLActive ? "lock.fill" : "lock.open"
        }
    }

    private var headerText: String {
        guard connection != nil else { return "Not connected" }
        return isSSLActive ? "Encrypted connection" : "Connection details"
    }

    // MARK: - Rows

    private struct Row { let label: String; let value: String }

    private var rows: [Row] {
        guard let c = connection else { return [] }
        switch c.engine {
        case .postgres:
            return [
                Row(label: "Engine",     value: "PostgreSQL"),
                Row(label: "Host",       value: c.host),
                Row(label: "Port",       value: c.port),
                Row(label: "Database",   value: c.databaseName),
                Row(label: "User",       value: c.username),
                Row(label: "SSL mode",   value: c.sslMode.label),
                Row(label: "Encryption", value: isSSLActive ? "SSL/TLS (active)" : "Not encrypted"),
            ]
        case .sqlite:
            let path = (c.filePath as NSString).expandingTildeInPath
            return [
                Row(label: "Engine", value: "SQLite"),
                Row(label: "File",   value: (path as NSString).lastPathComponent),
                Row(label: "Path",   value: path),
            ]
        }
    }
}
