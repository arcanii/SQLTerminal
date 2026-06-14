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
// DatabaseSession.swift
// SQLTerminal

import Foundation

/// Hosts a `DatabaseProvider` — and the synchronous, non-`Sendable` database
/// connection it wraps — on a single dedicated serial queue, off the main actor.
///
/// Every blocking call (`connect`, `execute`, `disconnect`) runs on `queue`, so
/// the `@MainActor` UI thread is never blocked by network or disk I/O, and the
/// provider is only ever touched by one thread at a time — satisfying
/// PostgresClientKit's "no more than one thread may concurrently operate against
/// a Connection" rule.
///
/// The sole exception is ``cancel()``, which is deliberately invoked from another
/// thread to interrupt a query that is currently blocked on the queue. It relies
/// on each provider's thread-safe interruption primitive
/// (`Connection.closeAbruptly()` for Postgres, `sqlite3_interrupt()` for SQLite),
/// both of which are documented as safe to call while another thread is mid-query.
/// `lock` serialises `cancel()` against `connect`/`disconnect` so it can never
/// race the provider being replaced or torn down.
///
/// Each window owns its own `DatabaseSession` (hence its own queue and thread),
/// which keeps multi-window sessions fully independent.
nonisolated final class DatabaseSession: @unchecked Sendable {

    private let queue: DispatchQueue
    private let lock = NSLock()
    /// The live provider. Guarded by `lock` because `cancel()` reads it from a
    /// different thread than the queue that mutates it.
    private var provider: DatabaseProvider?

    init(label: String) {
        queue = DispatchQueue(label: label, qos: .userInitiated)
    }

    deinit {
        // Safety net for teardown; normally the owner has already disconnected.
        lock.withLock {
            provider?.disconnect()
            provider = nil
        }
    }

    /// Whether a provider is currently connected. Snapshot only — prefer the
    /// owning view model's mirrored state for UI.
    var isConnected: Bool {
        lock.withLock { provider?.isConnected ?? false }
    }

    /// Whether the live connection is encrypted. Read by the owning view model
    /// right after `connect` returns (when the provider's value is stably set).
    var isSSLActive: Bool {
        lock.withLock { provider?.isSSLActive ?? false }
    }

    // MARK: - Connect / disconnect

    /// Open a connection for `config`, replacing (and closing) any existing one.
    /// Runs entirely off the main thread.
    func connect(_ config: DatabaseConnection) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queue.async {
                // Tear down any previous provider before standing up the new one.
                self.lock.withLock {
                    self.provider?.disconnect()
                    self.provider = nil
                }

                let newProvider = DatabaseProviderFactory.provider(for: config.engine)
                do {
                    try newProvider.connect(with: config)
                    self.lock.withLock { self.provider = newProvider }
                    cont.resume()
                } catch {
                    // Leave the session disconnected; the caller decides how to recover.
                    cont.resume(throwing: error)
                }
            }
        }
    }

    /// Close the current connection, if any.
    func disconnect() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            queue.async {
                self.lock.withLock {
                    self.provider?.disconnect()
                    self.provider = nil
                }
                cont.resume()
            }
        }
    }

    // MARK: - Execute

    /// Execute `sql` off the main thread.
    ///
    /// If the surrounding `Task` is cancelled while the query is in flight, the
    /// provider is interrupted via ``cancel()`` (see ``DatabaseProvider/cancel()``).
    /// The interrupted call unblocks and returns — usually an error result, which
    /// the caller should discard in favour of a "cancelled" message.
    func execute(_ sql: String) async -> QueryResult {
        await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<QueryResult, Never>) in
                queue.async {
                    let provider = self.lock.withLock { self.provider }
                    let result = provider?.execute(sql: sql)
                        ?? .failure("No database connection.")
                    cont.resume(returning: result)
                }
            }
        } onCancel: {
            self.cancel()
        }
    }

    // MARK: - Cancel

    /// Interrupt an in-flight query. Safe to call from any thread; serialised
    /// against `connect`/`disconnect` by `lock`, and a no-op when idle.
    func cancel() {
        lock.withLock { provider?.cancel() }
    }
}
