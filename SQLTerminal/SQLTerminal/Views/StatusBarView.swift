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

