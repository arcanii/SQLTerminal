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

// KeyboardShortcuts.swift
// SQLTerminal

//
// 1. The `.commands { }` modifier on the WindowGroup in SQLTerminalApp.swift
//    — this adds it to the macOS menu bar and registers the global shortcut.
//
// 2. (Optional) A local NSEvent monitor below, useful if you ever need
//    additional non-menu shortcuts in the future.

import AppKit
import Combine

final class ShortcutMonitor {

    static let shared = ShortcutMonitor()
    private var monitor: Any?

    /// Call once at app launch if you need extra non-menu shortcuts.
    func startMonitoring(onOptionE: @escaping () -> Void) {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Option + E
            if event.modifierFlags.contains(.option),
               event.charactersIgnoringModifiers?.lowercased() == "e" {
                onOptionE()
                return nil      // consume the event
            }
            return event
        }
    }

    func stopMonitoring() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }
}

