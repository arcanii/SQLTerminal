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
// A non-secret snapshot of a connection, used for the Recents list. The password
// is never stored here — it lives in the Keychain (see KeychainHelper).

import Foundation

struct ConnectionProfile: Codable, Identifiable {
    var engine: DatabaseEngine
    var filePath: String
    var host: String
    var port: String
    var databaseName: String
    var username: String

    init(_ connection: DatabaseConnection) {
        engine       = connection.engine
        filePath     = connection.filePath
        host         = connection.host
        port         = connection.port
        databaseName = connection.databaseName
        username     = connection.username
    }

    /// Stable identity for dedup and as a `List`/`ForEach` id.
    var id: String {
        switch engine {
        case .sqlite:   return "sqlite:\(filePath)"
        case .postgres: return "postgres:\(username)@\(host):\(port)/\(databaseName)"
        }
    }

    var displayName: String {
        switch engine {
        case .sqlite:
            let name = (filePath as NSString).lastPathComponent
            return "SQLite — \(name.isEmpty ? filePath : name)"
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

/// Persists the most-recently-used connection profiles in UserDefaults.
enum RecentConnectionsStore {
    private static let key = "recentConnections"
    private static let maxCount = 10

    static func load() -> [ConnectionProfile] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([ConnectionProfile].self, from: data)
        else { return [] }
        return list
    }

    /// Insert/refresh a profile at the top (dedup by identity, capped).
    static func add(_ profile: ConnectionProfile) {
        guard profile.isValid else { return }
        var list = load().filter { $0.id != profile.id }
        list.insert(profile, at: 0)
        if list.count > maxCount { list = Array(list.prefix(maxCount)) }
        save(list)
    }

    static func remove(_ profile: ConnectionProfile) {
        save(load().filter { $0.id != profile.id })
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    private static func save(_ list: [ConnectionProfile]) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
