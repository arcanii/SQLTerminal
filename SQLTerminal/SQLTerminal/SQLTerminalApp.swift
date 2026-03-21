// SQLTerminalApp.swift
// SQLTerminal

import SwiftUI

@main
struct SQLTerminalApp: App {
    @StateObject private var terminalVM = TerminalViewModel()

    var body: some Scene {
        WindowGroup {
            TerminalView()
                .environmentObject(terminalVM)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1100, height: 750)
        .commands {
            CommandGroup(after: .textEditing) {
                Button("Execute Query") {
                    terminalVM.executeCurrentQuery()
                }
                .keyboardShortcut("e", modifiers: .command)

                Divider()

                Button("Previous Command") {
                    terminalVM.navigateHistoryUp()
                }
                .keyboardShortcut(.upArrow, modifiers: .command)

                Button("Next Command") {
                    terminalVM.navigateHistoryDown()
                }
                .keyboardShortcut(.downArrow, modifiers: .command)
            }
        }
    }
}
