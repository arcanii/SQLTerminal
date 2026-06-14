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
// PostgresHBA.swift
// SQLTerminal / SQLCore

import Foundation

/// Pure helpers for turning a Postgres "no pg_hba.conf entry for host …"
/// rejection into the exact `host` rule that would let the connection in.
/// Extracted from `PostgresProvider` so it can be unit-tested without a server.
nonisolated enum PostgresHBA {

    /// If `message` is a Postgres "no pg_hba.conf entry for host …" rejection,
    /// returns the `pg_hba.conf` line that would permit the connection. Postgres
    /// phrases the rejection as:
    ///
    ///     no pg_hba.conf entry for host "ADDR", user "USER", database "DB", no encryption
    ///
    /// so the three quoted values are exactly the fields a `host` rule needs.
    static func suggestedLine(fromServerMessage message: String) -> String? {
        guard message.contains("no pg_hba.conf entry") else { return nil }

        let quoted = quotedValues(in: message)
        guard quoted.count >= 3 else { return nil }

        let rawAddress = quoted[0]
        let user = quoted[1]
        let database = quoted[2]

        // Strip any IPv6 zone index (e.g. "%en0") — it isn't valid in pg_hba.conf.
        let address = String(rawAddress.split(separator: "%").first ?? Substring(rawAddress))

        // This client always connects over TCP, so we expect an IP literal; if
        // it isn't one, don't risk suggesting a malformed rule.
        guard address.contains(".") || address.contains(":") else { return nil }

        // Single-host CIDR: /32 for IPv4, /128 for IPv6.
        let cidr = address.contains(":") ? "\(address)/128" : "\(address)/32"

        return "host    \(database)    \(user)    \(cidr)    scram-sha-256"
    }

    /// The substrings enclosed in double quotes, in order of appearance.
    static func quotedValues(in string: String) -> [String] {
        var values: [String] = []
        var current = ""
        var inQuote = false
        for ch in string {
            if ch == "\"" {
                if inQuote { values.append(current); current = "" }
                inQuote.toggle()
            } else if inQuote {
                current.append(ch)
            }
        }
        return values
    }
}
