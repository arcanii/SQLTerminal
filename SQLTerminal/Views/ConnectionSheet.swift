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

// ConnectionSheet.swift
// SQLTerminal

import SwiftUI
import Combine
import UniformTypeIdentifiers

struct ConnectionSheet: View {
    @EnvironmentObject var terminalVM: TerminalViewModel
    @StateObject private var vm = ConnectionViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {

            // ── Header ──
            header

            Divider()

            // ── Form ──
            Form {
                enginePicker
                if vm.connection.engine == .sqlite {
                    sqliteFields
                } else {
                    serverFields
                }
            }
            .formStyle(.grouped)
            .padding()

            Divider()

            // ── Error ──
            if let error = vm.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }

            // ── Buttons ──
            HStack {
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Connect") {
                    attemptConnection()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!vm.canConnect)
            }
            .padding()
        }
        .frame(width: 520, height: 380)
    }

    // MARK: - Sub-views

    private var header: some View {
        VStack(spacing: 4) {
            Image(systemName: "server.rack")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Connect to Database")
                .font(.headline)
            Text("Choose an engine and provide connection details.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    private var enginePicker: some View {
        Picker("Engine", selection: $vm.connection.engine) {
            ForEach(DatabaseEngine.allCases) { engine in
                Text(engine.rawValue).tag(engine)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: vm.connection.engine) { _, newValue in
            vm.connection.port = newValue.defaultPort
            vm.errorMessage = nil
        }
    }

    private var sqliteFields: some View {
        Section("SQLite File") {
            HStack {
                TextField("Database path", text: $vm.connection.filePath)
                    .textFieldStyle(.roundedBorder)
                Button("Open…") {
                    vm.browseForFile()
                }
                Button("New…") {
                    vm.browseForNewFile()
                }
            }
            Text("Use \"Open\" for existing files, \"New\" to create a database.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var serverFields: some View {
        Section("Server Details") {
            TextField("Host", text: $vm.connection.host)
                .textFieldStyle(.roundedBorder)
            TextField("Port", text: $vm.connection.port)
                .textFieldStyle(.roundedBorder)
            TextField("Database", text: $vm.connection.databaseName)
                .textFieldStyle(.roundedBorder)
            TextField("Username", text: $vm.connection.username)
                .textFieldStyle(.roundedBorder)
            SecureField("Password", text: $vm.connection.password)
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - Actions

    private func attemptConnection() {
        vm.errorMessage = nil
        vm.connection.securityScopedURL = vm.securityScopedURL
        terminalVM.connect(with: vm.connection)
        if terminalVM.isConnected {
            vm.saveLastConnection()
            dismiss()
        } else {
            vm.errorMessage = "Connection failed. Check your settings."
        }
    }

}

