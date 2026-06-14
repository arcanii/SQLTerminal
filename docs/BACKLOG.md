# SQLTerminal — Backlog

Candidate features and known gaps. Effort is a rough T-shirt size (S / M / L).
Nothing in *Candidates* is committed work — it's a planning list.

## ✅ Done

- **Connection manager** — recent connections, saved/named profiles, Keychain
  password storage, show/hide password.
- **SSL/TLS for PostgreSQL** — Off / Prefer / Require, with a status-bar lock
  when the connection is actually encrypted, and a click-through connection-
  details popover.
- **Off-main-thread query execution** — execution (and connect/reconnect) runs
  off the main thread behind a `DatabaseSession`; the UI stays responsive and a
  running query can be cancelled (⌘.). An unreachable host no longer hangs the
  app.
- **Run selection / statement-at-cursor** — ⌘↩ runs the selection or the
  statement under the cursor; ⌘E still runs the whole editor.
- **Read-only mode** — per-window toggle that blocks writes/DDL.
- **Confirm destructive statements** — prompts on `DROP`, `TRUNCATE`, or a
  `DELETE`/`UPDATE` without a `WHERE`.
- **Transaction handling** — Begin / Commit / Rollback controls with an
  in-transaction indicator.
- **Schema sidebar / object browser** — tables → columns tree; click to drop a
  `SELECT` in the editor or preview rows.
- **Tests** — pure SQL logic (statement splitter, classifier, `pg_hba`
  formatting) extracted to a `SQLCore` package with a `swift test` suite.

## Candidates

### Editor & results UX
- **Persistent, searchable query history + snippets** (M) — history currently
  dies with the window.
- **Sortable result columns + cell detail view** (M) — click-to-sort headers;
  expand long text / JSON cell values.
- **SQL syntax highlighting** (M) — in the editor.

### Foundational
- **MySQL / MariaDB engine** (M–L) — the `DatabaseProvider` protocol + factory
  make a third engine straightforward and widen the audience.
