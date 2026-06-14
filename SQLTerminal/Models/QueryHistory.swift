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
// QueryHistory.swift
// SQLTerminal
//
// Persistent, app-wide query history and named snippets. Unlike the per-window
// ⌘↑/⌘↓ command history, these survive launches and are shared across windows,
// stored as JSON in UserDefaults (same approach as ConnectionProfile stores).

import Foundation

/// A previously-executed query, remembered across launches.
struct QueryHistoryEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var sql: String
    var lastRun: Date
    var runCount: Int
}

/// A saved, named, reusable query.
struct QuerySnippet: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var sql: String
}

/// Persists recently-executed queries (auto, capped, deduped by SQL text,
/// most-recent first).
enum QueryHistoryStore {
    private static let key = "queryHistory"
    private static let maxCount = 200

    static func load() -> [QueryHistoryEntry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([QueryHistoryEntry].self, from: data)
        else { return [] }
        return list
    }

    /// Record an executed query: move an existing identical one to the top
    /// (bumping its count/date), or insert a new entry.
    static func record(_ rawSQL: String, now: Date = Date()) {
        let sql = rawSQL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sql.isEmpty else { return }

        var list = load()
        if let idx = list.firstIndex(where: { $0.sql == sql }) {
            var entry = list.remove(at: idx)
            entry.lastRun = now
            entry.runCount += 1
            list.insert(entry, at: 0)
        } else {
            list.insert(QueryHistoryEntry(sql: sql, lastRun: now, runCount: 1), at: 0)
        }
        if list.count > maxCount { list = Array(list.prefix(maxCount)) }
        save(list)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    private static func save(_ list: [QueryHistoryEntry]) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

/// Persists named snippets (no eviction; sorted by name).
enum SnippetStore {
    private static let key = "querySnippets"

    static func load() -> [QuerySnippet] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([QuerySnippet].self, from: data)
        else { return [] }
        return list
    }

    /// Upsert by (case-insensitive) name.
    static func save(name rawName: String, sql rawSQL: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let sql = rawSQL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !sql.isEmpty else { return }

        var list = load().filter { $0.name.localizedCaseInsensitiveCompare(name) != .orderedSame }
        list.append(QuerySnippet(name: name, sql: sql))
        list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        persist(list)
    }

    static func remove(_ snippet: QuerySnippet) {
        persist(load().filter { $0.id != snippet.id })
    }

    private static func persist(_ list: [QuerySnippet]) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
