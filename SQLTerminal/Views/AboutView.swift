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
// AboutView.swift
// SQLTerminal

import SwiftUI
import AppKit

struct AboutView: View {
    private let appVersion: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Version \(version) (\(build))"
    }()

    var body: some View {
        VStack(spacing: 16) {

            // App icon
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 96, height: 96)
            }

            // App name
            Text("SQLTerminal")
                .font(.system(size: 24, weight: .bold))

            // Version
            Text(appVersion)
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()
                .frame(width: 200)

            // Description
            VStack(spacing: 8) {
                Text("A simple SQL terminal for macOS")
                    .font(.body)

                Text("Supports SQLite and PostgreSQL")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Divider()
                .frame(width: 200)

            // Credits
            VStack(spacing: 4) {
                Text("Built with Swift & SwiftUI")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("PostgresClientKit by codewinsdotcom")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Links
            HStack(spacing: 16) {
                Button("GitHub") {
                    if let url = URL(string: "https://github.com/arcanii/SQLTerminal") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link)

                Button("Report Issue") {
                    if let url = URL(string: "https://github.com/arcanii/SQLTerminal/issues") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link)
            }
            .font(.caption)

            // Copyright
            Text("© 2026 bryan.mark@gmail.com All rights reserved.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            
            Text("for Daniel Kenny and Bryan Mark")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(30)
        .frame(width: 350)
    }
}
