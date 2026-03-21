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
// SessionView.swift
// SQLTerminal

import SwiftUI
import Combine
import AppKit

struct SessionView: View {
    @StateObject private var terminalVM = TerminalViewModel()

    var body: some View {
        TerminalView()
            .environmentObject(terminalVM)
            .frame(minWidth: 900, minHeight: 600)
            .background(WindowAccessor(vm: terminalVM))
            .navigationTitle(windowTitle)
            .onDisappear {
                terminalVM.disconnectAndPromptReconnect()
            }
    }

    private var windowTitle: String {
        guard terminalVM.isConnected, let info = terminalVM.connectionInfo else {
            return "SQLTerminal — Not Connected"
        }

        switch info.engine {
        case .sqlite:
            let fileName = (info.filePath as NSString).lastPathComponent
            return "SQLite — \(fileName)"
        case .postgres:
            return "PostgreSQL — \(info.databaseName) (\(info.username)@\(info.host):\(info.port))"
        }
    }
}

// MARK: - Window Accessor

struct WindowAccessor: NSViewRepresentable {
    let vm: TerminalViewModel

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                SessionRegistry.shared.register(window: window, vm: vm)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                SessionRegistry.shared.register(window: window, vm: vm)
            }
        }
    }
}

