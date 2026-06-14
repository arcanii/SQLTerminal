#!/usr/bin/env bash
#
# build.sh — produce a signed, notarized, Sparkle-signed SQLTerminal DMG.
#
# Pipeline:
#   archive (Developer ID) -> export -> create-dmg -> notarize -> staple
#   -> Sparkle sign_update -> print the appcast <enclosure> line to paste.
#
# One-time setup (see docs/RELEASING.md):
#   * Developer ID Application certificate in your keychain (team 386M76FV3K)
#   * A notarytool keychain profile (NOTARY_PROFILE below):
#       xcrun notarytool store-credentials "SQLTerminal-notarize" \
#           --apple-id <you@example.com> --team-id 386M76FV3K --password <app-specific-pwd>
#   * The Sparkle EdDSA private key (already generated, stored in your login
#     keychain under account "SQLTerminal"). BACK IT UP — losing it means you can
#     never ship another update to existing installs. Export a backup with:
#       <sparkle>/bin/generate_keys --account SQLTerminal -x sqlterminal_sparkle_key.backup
#   * Homebrew create-dmg:  brew install create-dmg
#
# Per-machine overrides go in scripts/build.config (gitignored).

set -euo pipefail

# ---- Repo paths ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_DIR}"

PROJECT="SQLTerminal.xcodeproj"
SCHEME="SQLTerminal"
PRODUCT_NAME="SQLTerminal"
CONFIGURATION="Release"
GITHUB_REPO="arcanii/SQLTerminal"

# ---- Configurable (override in scripts/build.config) ----
DEVELOPMENT_TEAM="386M76FV3K"
NOTARY_PROFILE="SQLTerminal-notarize"
SPARKLE_KEY_ACCOUNT="SQLTerminal"   # keychain account holding the EdDSA private key
SIGN_UPDATE="${SIGN_UPDATE:-}"      # optional explicit path to Sparkle's sign_update

[ -f "${SCRIPT_DIR}/build.config" ] && source "${SCRIPT_DIR}/build.config"

# ---- Preflight ----
command -v xcodebuild >/dev/null || { echo "ERROR: xcodebuild not found"; exit 1; }
command -v create-dmg >/dev/null || { echo "ERROR: create-dmg not found — 'brew install create-dmg'"; exit 1; }

# ---- Version from the project ----
read_setting() {
    xcodebuild -project "${PROJECT}" -scheme "${SCHEME}" -configuration "${CONFIGURATION}" \
        -showBuildSettings 2>/dev/null | awk -v k="$1" '$1==k {print $3; exit}'
}
VERSION="$(read_setting MARKETING_VERSION)"
BUILD="$(read_setting CURRENT_PROJECT_VERSION)"
[ -n "${VERSION}" ] || { echo "ERROR: could not read MARKETING_VERSION"; exit 1; }
echo "==> ${PRODUCT_NAME} ${VERSION} (build ${BUILD})"

# ---- Output layout ----
OUT_DIR="${REPO_DIR}/build/${PRODUCT_NAME}-${CONFIGURATION}-${VERSION}"
ARCHIVE_PATH="${OUT_DIR}/${PRODUCT_NAME}.xcarchive"
EXPORT_DIR="${OUT_DIR}/export"
DMG_PATH="${OUT_DIR}/${PRODUCT_NAME}-v${VERSION}.dmg"
rm -rf "${OUT_DIR}"; mkdir -p "${OUT_DIR}"

# ---- Archive ----
echo "==> Archiving…"
xcodebuild archive \
    -project "${PROJECT}" -scheme "${SCHEME}" -configuration "${CONFIGURATION}" \
    -archivePath "${ARCHIVE_PATH}" \
    -destination "generic/platform=macOS" \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM}" >"${OUT_DIR}/archive.log" 2>&1 || {
        echo "ERROR: archive failed — see ${OUT_DIR}/archive.log"; tail -20 "${OUT_DIR}/archive.log"; exit 1; }

# ---- Export (Developer ID) ----
echo "==> Exporting (Developer ID)…"
EXPORT_PLIST="${OUT_DIR}/ExportOptions.plist"
cat > "${EXPORT_PLIST}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>method</key><string>developer-id</string>
    <key>signingStyle</key><string>automatic</string>
    <key>teamID</key><string>${DEVELOPMENT_TEAM}</string>
</dict></plist>
PLIST
xcodebuild -exportArchive \
    -archivePath "${ARCHIVE_PATH}" \
    -exportPath "${EXPORT_DIR}" \
    -exportOptionsPlist "${EXPORT_PLIST}" \
    -allowProvisioningUpdates >"${OUT_DIR}/export.log" 2>&1 || {
        echo "ERROR: export failed — see ${OUT_DIR}/export.log"; tail -20 "${OUT_DIR}/export.log"; exit 1; }
APP_PATH="${EXPORT_DIR}/${PRODUCT_NAME}.app"

# ---- DMG ----
echo "==> Creating DMG…"
create-dmg \
    --volname "${PRODUCT_NAME} ${VERSION}" \
    --window-size 600 400 --icon-size 120 \
    --icon "${PRODUCT_NAME}.app" 150 190 \
    --hide-extension "${PRODUCT_NAME}.app" \
    --app-drop-link 450 190 \
    "${DMG_PATH}" "${APP_PATH}" || true   # create-dmg exits non-zero on benign warnings
[ -f "${DMG_PATH}" ] || { echo "ERROR: DMG not created"; exit 1; }

# ---- Notarize + staple ----
echo "==> Notarizing (profile: ${NOTARY_PROFILE})…"
xcrun notarytool submit "${DMG_PATH}" --keychain-profile "${NOTARY_PROFILE}" --wait
echo "==> Stapling…"
xcrun stapler staple "${DMG_PATH}"

# ---- Sparkle EdDSA signature ----
echo "==> Signing the update (Sparkle)…"
if [ -z "${SIGN_UPDATE}" ]; then
    SIGN_UPDATE="$(find "${HOME}/Library/Developer/Xcode/DerivedData" -path '*/artifacts/sparkle/Sparkle/bin/sign_update' 2>/dev/null | head -1)"
fi
[ -n "${SIGN_UPDATE}" ] && [ -x "${SIGN_UPDATE}" ] || { echo "ERROR: sign_update not found — set SIGN_UPDATE in build.config"; exit 1; }
SIG_LINE="$("${SIGN_UPDATE}" --account "${SPARKLE_KEY_ACCOUNT}" "${DMG_PATH}")"

cat <<DONE

================================================================
 Built:  ${DMG_PATH}

 1) Create the GitHub release and upload the DMG:
      gh release create "v${VERSION}" "${DMG_PATH}" \\
          --title "v${VERSION}" --notes-file docs/RELEASES/v${VERSION}.md

 2) Add a new <item> to the TOP of appcast.xml with this enclosure,
    then commit & push appcast.xml:

    <enclosure
        url="https://github.com/${GITHUB_REPO}/releases/download/v${VERSION}/${PRODUCT_NAME}-v${VERSION}.dmg"
        ${SIG_LINE}
        type="application/octet-stream"/>
================================================================
DONE
