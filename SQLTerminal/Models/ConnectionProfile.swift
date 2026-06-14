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
// ConnectionProfile.swift
// SQLTerminal
//
// A non-secret snapshot of a connection. Used for both the auto Recents list
// (no name) and explicitly Saved profiles (named). The password is never stored
// here — it lives in the Keychain (see KeychainHelper).

import Foundation

struct ConnectionProfile: Codable, Identifiable {
    /// Set for saved profiles ("Prod", "Local dev"); nil for recents.
    var name: String?
    var engine: DatabaseEngine
    var filePath: String
    var host: String
    var port: String
    var databaseName: String
    var username: String

    init(_ connection: DatabaseConnection, name: String? = nil) {
        self.name    = name
        engine       = connection.engine
        filePath     = connection.filePath
        host         = connection.host
        port         = connection.port
        databaseName = connection.databaseName
        username     = connection.username
    }

    /// Stable identity: by name for saved profiles, by connection for recents.
    var id: String {
        if let name, !name.isEmpty { return "named:\(name)" }
        switch engine {
        case .sqlite:   return "sqlite:\(filePath)"
        case .postgres: return "postgres:\(username)@\(host):\(port)/\(databaseName)"
        }
    }

    var displayName: String {
        if let name, !name.isEmpty { return name }
        switch engine {
        case .sqlite:
            let n = (filePath as NSString).lastPathComponent
            return "SQLite — \(n.isEmpty ? filePath : n)"
        case .postgres:
            return "\(username)@\(host):\(port)/\(databaseName)"
        }
    }

    /// Whether this profile carries enough to be worth remembering.
    var isValid: Bool {
        switch engine {
        case .sqlite:   return !filePath.isEmpty
        case .postgres: return !host.isEmpty && !databaseName.isEmpty && !username.isEmpty
        }
    }
}

/// Persists the most-recently-used connections (auto, capped, deduped).
enum RecentConnectionsStore {
    private static let key = "recentConnections"
    private static let maxCount = 10

    static func load() -> [ConnectionProfile] {
        decode(key)
    }

    static func add(_ profile: ConnectionProfile) {
        guard profile.isValid else { return }
        var list = load().filter { $0.id != profile.id }
        list.insert(profile, at: 0)
        if list.count > maxCount { list = Array(list.prefix(maxCount)) }
        encode(list, key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

/// Persists explicitly saved, named profiles (no eviction; sorted by name).
enum SavedProfilesStore {
    private static let key = "savedProfiles"

    static func load() -> [ConnectionProfile] {
        decode(key)
    }

    static func save(_ profile: ConnectionProfile) {
        guard profile.isValid else { return }
        var list = load().filter { $0.id != profile.id }
        list.append(profile)
        list.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        encode(list, key)
    }

    static func remove(_ profile: ConnectionProfile) {
        encode(load().filter { $0.id != profile.id }, key)
    }
}

// MARK: - Shared JSON helpers

private func decode(_ key: String) -> [ConnectionProfile] {
    guard let data = UserDefaults.standard.data(forKey: key),
          let list = try? JSONDecoder().decode([ConnectionProfile].self, from: data)
    else { return [] }
    return list
}

private func encode(_ list: [ConnectionProfile], _ key: String) {
    if let data = try? JSONEncoder().encode(list) {
        UserDefaults.standard.set(data, forKey: key)
    }
}
