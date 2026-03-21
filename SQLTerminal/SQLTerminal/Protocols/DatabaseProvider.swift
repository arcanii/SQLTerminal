// DatabaseProvider.swift
// SQLTerminal

import Foundation

/// **The single protocol every database engine must implement.**
///
/// To add PostgreSQL support later, create a class that conforms to
/// `DatabaseProvider` and you're done — the UI doesn't change at all.
protocol DatabaseProvider: AnyObject {

    /// Which engine this provider represents.
    var engine: DatabaseEngine { get }

    /// Whether the provider currently has an open connection.
    var isConnected: Bool { get }

    /// Human-readable status, e.g. "Connected to mydb.sqlite".
    var statusMessage: String { get }

    /// Open a connection using the given configuration.
    func connect(with connection: DatabaseConnection) throws

    /// Close the current connection and release resources.
    func disconnect()

    /// Execute arbitrary SQL and return a unified `QueryResult`.
    func execute(sql: String) -> QueryResult
}

