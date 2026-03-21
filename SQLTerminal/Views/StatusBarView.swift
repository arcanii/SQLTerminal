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
// StatusBarView.swift
// SQLTerminal

import SwiftUI

struct StatusBarView: View {
    @EnvironmentObject var vm: TerminalViewModel

    var body: some View {
        HStack(spacing: 12) {
            // Connection indicator
            Circle()
                .fill(vm.isConnected ? Color.green : Color.red)
                .frame(width: 8, height: 8)

            Text(vm.connectionInfo?.displayName ?? "Not connected")
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)

            Spacer()

            Text("⌘E Execute  ⌘↑ Prev  ⌘↓ Next")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.15))
                )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

