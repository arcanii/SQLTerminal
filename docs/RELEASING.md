# Releasing SQLTerminal

SQLTerminal ships signed, notarized DMGs via GitHub Releases and auto-updates
through [Sparkle](https://sparkle-project.org). The update feed is `appcast.xml`,
served from `https://raw.githubusercontent.com/arcanii/SQLTerminal/main/appcast.xml`
(the `SUFeedURL` in the app's Info.plist).

## One-time setup

1. **Developer ID certificate** — team `386M76FV3K` needs a "Developer ID
   Application" certificate in your login keychain (the same one Usage4Claude
   uses).

2. **Notarization profile**:
   ```sh
   xcrun notarytool store-credentials "SQLTerminal-notarize" \
       --apple-id you@example.com --team-id 386M76FV3K --password <app-specific-password>
   ```
   Create the app-specific password at <https://appleid.apple.com>.

3. **Sparkle signing key** — already generated; the private key lives in your
   login keychain under account `SQLTerminal`, and its public half is in the
   app's Info.plist (`SUPublicEDKey`). **Back it up and store it safely** — if you
   lose it you can never ship another update to existing installs:
   ```sh
   # <sparkle> = .../SourcePackages/artifacts/sparkle/Sparkle in your DerivedData
   <sparkle>/bin/generate_keys --account SQLTerminal -x sqlterminal_sparkle_key.backup
   ```

4. **create-dmg**: `brew install create-dmg`

5. Optional: copy `scripts/build.config.example` to `scripts/build.config` to
   override any of the above per machine.

## Cutting a release

1. **Bump the version in Xcode** (both must increase):
   - `MARKETING_VERSION` (e.g. `0.1.1` → `0.1.2`) — user-facing version.
   - `CURRENT_PROJECT_VERSION` (e.g. `1` → `2`) — the numeric build number Sparkle
     compares (`sparkle:version`).

2. **Write release notes** in `docs/RELEASES/v<version>.md`.

3. **Build** the signed/notarized DMG:
   ```sh
   ./scripts/build.sh
   ```
   This archives with Developer ID, notarizes, staples, signs the update with
   Sparkle, and prints (a) the `gh release create` command and (b) the
   `<enclosure>` line for the appcast.

4. **Publish the GitHub release** (the script prints the exact command), e.g.:
   ```sh
   gh release create v0.1.2 build/SQLTerminal-Release-0.1.2/SQLTerminal-v0.1.2.dmg \
       --title "v0.1.2" --notes-file docs/RELEASES/v0.1.2.md
   ```

5. **Update the appcast**: add a new `<item>` to the TOP of `appcast.xml` using
   the printed `<enclosure>` (fill in `title`, `pubDate`, `sparkle:version` =
   `CURRENT_PROJECT_VERSION`, `sparkle:shortVersionString` = `MARKETING_VERSION`,
   `link`, and `description`), then commit and push `appcast.xml` to `main`.

Existing installs poll the appcast and present the update.

## How it's wired

- **Dependency**: Sparkle 2.x via Swift Package Manager.
- **Updater**: `SPUStandardUpdaterController` owned by `SQLTerminalApp`, with a
  self-disabling "Check for Updates…" item under the app menu
  (`SQLTerminal/Utilities/SparkleUpdater.swift`).
- **Info.plist** keys (injected via `INFOPLIST_KEY_*` build settings, since the
  plist is auto-generated): `SUFeedURL`, `SUPublicEDKey`, `SUEnableAutomaticChecks`.
- **No App Sandbox** (Hardened Runtime on), so Sparkle needs no XPC entitlements —
  simpler than a sandboxed app.
