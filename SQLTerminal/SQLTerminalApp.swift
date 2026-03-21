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
// SQLTerminalApp.swift
// SQLTerminal

import SwiftUI
import AppKit

@main
struct SQLTerminalApp: App {
    @State private var monitorInstalled = false

    var body: some Scene {
        WindowGroup {
            SessionView()
                .onAppear {
                    if !monitorInstalled {
                        installKeyMonitor()
                        monitorInstalled = true
                    }
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1100, height: 750)
    }

    private func installKeyMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            // ⌘E — Execute
            if flags.contains(.command),
               !flags.contains(.shift),
               !flags.contains(.option),
               !flags.contains(.control),
               event.keyCode == 14 {
                // Find the active window's TerminalViewModel
                if let vm = activeTerminalVM() {
                    vm.executeCurrentQuery()
                    return nil
                }
            }

            // ⌘↑ — Previous command
            if flags.contains(.command),
               event.keyCode == 126 {
                if let vm = activeTerminalVM() {
                    vm.navigateHistoryUp()
                    return nil
                }
            }

            // ⌘↓ — Next command
            if flags.contains(.command),
               event.keyCode == 125 {
                if let vm = activeTerminalVM() {
                    vm.navigateHistoryDown()
                    return nil
                }
            }

            return event
        }
    }

    /// Finds the TerminalViewModel for the currently active window
    private func activeTerminalVM() -> TerminalViewModel? {
        guard let window = NSApp.keyWindow else { return nil }
        guard let contentView = window.contentView else { return nil }

        // Walk the hosting view to find our SessionView's view model
        // The NSEvent is already scoped to the key window, so we use
        // a shared registry instead
        return SessionRegistry.shared.viewModel(for: window)
    }
}

// MARK: - Session Registry

/// Tracks which TerminalViewModel belongs to which window
final class SessionRegistry {
    static let shared = SessionRegistry()
    private var sessions: [ObjectIdentifier: TerminalViewModel] = [:]

    func register(window: NSWindow, vm: TerminalViewModel) {
        sessions[ObjectIdentifier(window)] = vm
    }

    func unregister(window: NSWindow) {
        sessions.removeValue(forKey: ObjectIdentifier(window))
    }

    func viewModel(for window: NSWindow) -> TerminalViewModel? {
        sessions[ObjectIdentifier(window)]
    }
}
