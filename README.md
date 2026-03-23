# SQLTerminal
A native macOS SQL terminal built with SwiftUI. Connect to SQLite or PostgreSQL databases and run queries with a clean, minimal interface.

![macOS](https://img.shields.io/badge/macOS-13.0+-blue)
![Swift](https://img.shields.io/badge/Swift-6-orange)
![License](https://img.shields.io/badge/License-GPL--3.0-blue)


## Overview
SQLTerminal brings a nostalgic terminal feel to database management. Write SQL in the bottom pane, hit **⌘E** to execute, and see results in the top pane.
Use command-arrows (⌘↑↓) for history replay.

|Version|Date|Description|
|-------|----|-----------|
|0.1.1 | March 23, 2026|Initial version - SQLite, Postgres|

## Features

### Database Support
- **SQLite** — Connect to existing databases or create new ones
- **PostgreSQL** — Connect with automatic authentication method detection (SCRAM-SHA-256, MD5, plaintext, trust)

### Terminal Interface
- Split-pane layout with draggable divider
- Syntax-safe input (smart quotes auto-corrected to straight quotes)
- Command history with **⌘↑** / **⌘↓**
- Multi-statement execution (separated by `;`)
- Dot-commands for common operations (`.tables`, `.schema`, `.help`)

### Results
- Tabular output with alternating row shading
- Right-click any row or cell to copy
- Export full results as **TSV** or **CSV** (paste directly into Excel/Numbers)
- Horizontal and vertical scrolling for wide/tall result sets

### Multi-Session
- **⌘N** opens a new window with an independent database connection
- Each window maintains its own session, history, and connection
- Mix SQLite and PostgreSQL sessions side by side
- Window title shows engine, database name, and user

### Dot-Commands

| Command | Description |
|---------|-------------|
| `.tables` | List all tables |
| `.views` | List all views |
| `.indexes [table]` | List indexes |
| `.schema [table]` | Show CREATE statements / column definitions |
| `.columns <table>` | Show column details |
| `.count <table>` | Count rows |
| `.first <table>` | Show first 10 rows |
| `.last <table>` | Show last 10 rows |
| `.fk <table>` | Show foreign keys |
| `.dbinfo` | Show database properties |
| `.size` | Show database size |
| `.encoding` | Show encoding |
| `.connect <database>` | Switch PostgreSQL database (keeps credentials) |
| `.databases` | List all PostgreSQL databases |
| `.schemas` | List all PostgreSQL schemas |
| `.clear` | Clear the terminal output |
| `.help` | Show all available commands |

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| **⌘E** | Execute query |
| **⌘↑** | Previous command from history |
| **⌘↓** | Next command from history |
| **⌘N** | New window / session |
| **⌘W** | Close window |

## Installation

### Build from Source / .dmg from releases

**Requirements:** Xcode 16+, macOS 13.0+

```bash
git clone https://github.com/arcanii/SQLTerminal.git
cd SQLTerminal
open SQLTerminal.xcodeproj
