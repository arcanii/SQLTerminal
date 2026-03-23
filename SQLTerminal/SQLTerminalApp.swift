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

        // About window
        Window("About SQLTerminal", id: "about") {
            AboutView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        // Wire the About menu item
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About SQLTerminal") {
                    NSApp.activate(ignoringOtherApps: true)
                    if let window = NSApp.windows.first(where: { $0.title == "About SQLTerminal" }) {
                        window.makeKeyAndOrderFront(nil)
                    } else {
                        // Open using the environment action
                        openAboutWindow()
                    }
                }
            }
        }
    }

    private func openAboutWindow() {
        let aboutView = NSHostingController(rootView: AboutView())
        let window = NSWindow(contentViewController: aboutView)
        window.title = "About SQLTerminal"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func installKeyMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            if flags.contains(.command),
               !flags.contains(.shift),
               !flags.contains(.option),
               !flags.contains(.control),
               event.keyCode == 14 {
                if let vm = activeTerminalVM() {
                    vm.executeCurrentQuery()
                    return nil
                }
            }

            if flags.contains(.command),
               event.keyCode == 126 {
                if let vm = activeTerminalVM() {
                    vm.navigateHistoryUp()
                    return nil
                }
            }

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

    private func activeTerminalVM() -> TerminalViewModel? {
        guard let window = NSApp.keyWindow else { return nil }
        return SessionRegistry.shared.viewModel(for: window)
    }
}

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
