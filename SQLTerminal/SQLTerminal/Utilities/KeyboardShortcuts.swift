// KeyboardShortcuts.swift
// SQLTerminal
//
// The actual Option-E shortcut is wired in TWO places for maximum reliability:
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

