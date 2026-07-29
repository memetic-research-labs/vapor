#!/usr/bin/env bash
# build-release.sh
# Builds, signs, notarizes, and staples a Vapor release DMG.
#
# Usage:
#   scripts/build-release.sh [output-dir]
#
# Notarization credentials, either:
#   NOTARY_KEYCHAIN_PROFILE            Profile from `xcrun notarytool store-credentials`
# or:
#   APPLE_ID                           Apple ID for notarization
#   APPLE_APP_SPECIFIC_PASSWORD        App-specific password (appleid.apple.com)
#
# Optional:
#   APPLE_TEAM_ID  Developer Team ID (default: YRQLJYMX5S)
#   OUTPUT_DIR     Directory for the final DMG (default: ./dist)
#
# Outputs:
#   $OUTPUT_DIR/Vapor-<version>-<build>.dmg
#   $OUTPUT_DIR/Vapor-<version>-<build>.sha256
#
# The DMG ships Vapor.app, the Chrome extension, and a versioned README,
# matching the layout users have been installing from.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$REPO_ROOT/Vapor/Vapor.xcodeproj"
SCHEME="Vapor"
DERIVED_DATA="$REPO_ROOT/.build/DerivedData"
ARCHIVE_PATH="$REPO_ROOT/.build/archives/Vapor.xcarchive"
EXPORT_DIR="$REPO_ROOT/.build/export"
OUTPUT_DIR="${1:-${OUTPUT_DIR:-$REPO_ROOT/dist}}"
EXPORT_OPTIONS="$REPO_ROOT/.build/ExportOptions.plist"
STAGING_DIR="$REPO_ROOT/.build/dmg-staging"
EXTENSION_SRC="$REPO_ROOT/vapor-extension"
README_TEMPLATE="$REPO_ROOT/scripts/dmg-readme.html.template"

APPLE_TEAM_ID="${APPLE_TEAM_ID:-YRQLJYMX5S}"
NOTARY_KEYCHAIN_PROFILE="${NOTARY_KEYCHAIN_PROFILE:-}"

# --- Validate env ---
# Either a stored keychain profile or an Apple ID plus app-specific password.
if [ -z "$NOTARY_KEYCHAIN_PROFILE" ]; then
  : "${APPLE_ID:?APPLE_ID (or NOTARY_KEYCHAIN_PROFILE) is required for notarization}"
  : "${APPLE_APP_SPECIFIC_PASSWORD:?APPLE_APP_SPECIFIC_PASSWORD (or NOTARY_KEYCHAIN_PROFILE) is required for notarization}"
fi

[ -d "$EXTENSION_SRC" ] || { echo "ERROR: Browser extension not found at $EXTENSION_SRC" >&2; exit 1; }
[ -f "$README_TEMPLATE" ] || { echo "ERROR: DMG README template not found at $README_TEMPLATE" >&2; exit 1; }

# Catch a bad override here rather than in an opaque xcodebuild export failure.
if ! printf '%s' "$APPLE_TEAM_ID" | grep -Eq '^[A-Z0-9]{10}$'; then
  echo "ERROR: APPLE_TEAM_ID must be 10 uppercase letters or digits (got: $APPLE_TEAM_ID)" >&2
  exit 1
fi

echo "=== Vapor Release Build ==="
echo "Repo:     $REPO_ROOT"
echo "Output:   $OUTPUT_DIR"
echo "Team ID:  $APPLE_TEAM_ID"
echo ""

mkdir -p "$OUTPUT_DIR" "$DERIVED_DATA" "$(dirname "$EXPORT_OPTIONS")"

# --- 0. Export options ---
# Generated from APPLE_TEAM_ID so the archive and the export cannot disagree
# about which team signs the app.
cat > "$EXPORT_OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>destination</key>
	<string>export</string>
	<key>method</key>
	<string>developer-id</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>teamID</key>
	<string>${APPLE_TEAM_ID}</string>
</dict>
</plist>
PLIST

# --- 1. Archive (Release, universal binary) ---
echo "[1/6] Archiving $SCHEME (Release)..."
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  -archivePath "$ARCHIVE_PATH" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  -quiet

# --- 2. Export signed .app ---
echo "[2/6] Exporting (Developer ID)..."
rm -rf "$EXPORT_DIR"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -exportPath "$EXPORT_DIR" \
  -quiet

APP_PATH="$EXPORT_DIR/Vapor.app"

if [ ! -d "$APP_PATH" ]; then
  echo "ERROR: Export did not produce Vapor.app"
  find "$EXPORT_DIR" -maxdepth 2
  exit 1
fi

# --- 3. Extract version ---
MARKETING_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
BUILD_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist")"
VERSION_TAG="${MARKETING_VERSION}-${BUILD_VERSION}"
DMG_NAME="Vapor-${VERSION_TAG}.dmg"
DMG_PATH="$OUTPUT_DIR/$DMG_NAME"

echo "  Version: $MARKETING_VERSION (build $BUILD_VERSION)"
echo "  DMG:     $DMG_NAME"

# --- 4. Stage DMG contents ---
# Vapor.app alone is not enough: users load the Chrome extension from the DMG,
# and the README explains how.
echo "[3/6] Staging DMG contents..."
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

cp -R "$APP_PATH" "$STAGING_DIR/Vapor.app"
cp -R "$EXTENSION_SRC" "$STAGING_DIR/Browser Extension"
sed -e "s|__VERSION__|${MARKETING_VERSION}|g" -e "s|__BUILD__|${BUILD_VERSION}|g" \
  "$README_TEMPLATE" > "$STAGING_DIR/README.html"

# Copying can drag along local noise; keep the image reproducible.
find "$STAGING_DIR/Browser Extension" -name '.DS_Store' -delete
rm -rf "$STAGING_DIR/Browser Extension/node_modules"

echo "  Vapor.app, Browser Extension, README.html"

# --- 5. Create DMG ---
echo "[4/6] Creating DMG..."
rm -f "$DMG_PATH"
hdiutil create \
  -volname "Vapor" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

# --- 6. Notarize ---
echo "[5/6] Submitting for notarization..."
if [ -n "$NOTARY_KEYCHAIN_PROFILE" ]; then
  xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" \
    --wait
else
  xcrun notarytool submit "$DMG_PATH" \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --team-id "$APPLE_TEAM_ID" \
    --wait
fi

# --- 7. Staple ---
echo "[6/6] Stapling notarization ticket..."
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

# --- 8. SHA256 ---
echo "Computing SHA256..."
SHASUM_PATH="$OUTPUT_DIR/${DMG_NAME%.dmg}.sha256"
shasum -a 256 "$DMG_PATH" | awk '{print $1}' > "$SHASUM_PATH"

echo ""
echo "=== Done ==="
echo "DMG:    $DMG_PATH"
echo "SHA256: $(cat "$SHASUM_PATH")"
echo ""
echo "Upload assets:"
echo "  $DMG_PATH"
echo "  $SHASUM_PATH"
