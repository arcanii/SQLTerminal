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
// DatabaseProviderFactory.swift
// SQLTerminal

import Foundation

/// Vends the correct provider for a given engine.
/// When you add a new engine, register it here.
enum DatabaseProviderFactory {

    static func provider(for engine: DatabaseEngine) -> DatabaseProvider {
        switch engine {
        case .sqlite:   return SQLiteProvider()
        case .postgres: return PostgresProvider()
        }
    }
}

