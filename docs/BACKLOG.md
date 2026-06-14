# SQLTerminal — Backlog

Candidate features and known gaps, grouped by theme. Effort is a rough T-shirt
size (S / M / L). Nothing here is committed work — it's a planning list.

## Connection manager
Best built together — recents + Keychain + saved profiles give one-click
reconnect with no re-typing.

- **Recent connections** (M) — remember the last N connections instead of only
  the single last one ([ConnectionViewModel](../SQLTerminal/ViewModels/ConnectionViewModel.swift)).
  Make `DatabaseConnection` `Codable` (excluding `password`), store a deduped,
  move-to-top list (~10) in UserDefaults / Application Support, and surface it as
  a "Recent" list in the connection sheet or a `File ▸ Open Recent` submenu.
- **Keychain password storage** (M) — save passwords with
  `kSecClassInternetPassword` (server / port / protocol / account) behind a
  "Save password" checkbox; retrieve on connect. Seamless via the already-unlocked
  login keychain. Caveat: Keychain ACLs are tied to the app's code-signing
  identity, so a dev build vs the Developer-ID release build may re-prompt.
- **Saved / named profiles** (M) — explicit bookmarks ("Prod", "Local dev")
  beyond auto-recents; a small connection manager.
- **Show / hide password toggle** (S) — an eye icon in the connection sheet to
  reveal what you're typing; toggle the field between `SecureField` and
  `TextField` ([ConnectionSheet](../SQLTerminal/Views/ConnectionSheet.swift)).

## Real-world gaps (high value)
- **SSL/TLS for Postgres** (M) — `ssl = false` is hardcoded in
  [PostgresProvider](../SQLTerminal/Providers/PostgresProvider.swift); managed
  Postgres (RDS, Supabase, Neon, Heroku, Azure) all require it, so none can
  connect today. Add an SSL mode (disable / require / verify-full) to the sheet.
- **Off-main-thread query execution** (M) — `execute()` runs on `@MainActor`
  ([TerminalViewModel](../SQLTerminal/ViewModels/TerminalViewModel.swift)); slow
  or blocked network queries freeze the UI and an unreachable host hangs the app.
  Run on a background task with a progress spinner + cancel.

## Editor & results UX
- **Schema sidebar / object browser** (L) — schemas → tables → columns tree;
  click to inspect or generate a `SELECT`.
- **Persistent, searchable query history + snippets** (M) — history currently
  dies with the window.
- **Run selection / statement-at-cursor** (S–M) — execute just the selected SQL
  or the statement under the cursor instead of the whole editor.
- **Sortable result columns + cell detail view** (M) — click-to-sort headers;
  expand long text / JSON cell values.
- **SQL syntax highlighting** (M) — in the editor.

## Safety
- **Read-only mode** (S) — block writes to guard against prod accidents.
- **Confirm destructive statements** (S) — prompt on `DROP`, or `DELETE` /
  `UPDATE` without a `WHERE`.

## Foundational
- **Tests** (M) — none today; the statement splitter, dot-command SQL, and the
  error / `pg_hba` formatting are pure and very testable.
- **MySQL / MariaDB engine** (M–L) — the `DatabaseProvider` protocol + factory
  make a third engine straightforward and widen the audience.

## Suggested order
1. Connection manager (recents + Keychain + saved profiles + show-password)
2. SSL/TLS for Postgres
3. Off-main-thread execution
4. Schema sidebar
