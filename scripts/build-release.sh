#!/usr/bin/env bash
# build-release.sh
# Builds, signs, notarizes, and staples a Vapor release DMG.
#
# Usage:
#   scripts/build-release.sh [output-dir]
#
# Required environment variables:
#   APPLE_ID                          Apple ID for notarization
#   APPLE_APP_SPECIFIC_PASSWORD        App-specific password (appleid.apple.com)
#   APPLE_TEAM_ID                      Developer Team ID (default: YRQLJYMX5S)
#
# Optional:
#   OUTPUT_DIR  Directory for the final DMG (default: ./dist)
#
# Outputs:
#   $OUTPUT_DIR/Vapor-<version>-<build>.dmg
#   $OUTPUT_DIR/Vapor-<version>-<build>.sha256

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$REPO_ROOT/Vapor/Vapor.xcodeproj"
SCHEME="Vapor"
DERIVED_DATA="$REPO_ROOT/.build/DerivedData"
ARCHIVE_PATH="$REPO_ROOT/.build/archives/Vapor.xcarchive"
EXPORT_DIR="$REPO_ROOT/.build/export"
OUTPUT_DIR="${1:-${OUTPUT_DIR:-$REPO_ROOT/dist}}"
EXPORT_OPTIONS="$REPO_ROOT/scripts/ExportOptions.plist"

APPLE_TEAM_ID="${APPLE_TEAM_ID:-YRQLJYMX5S}"

# --- Validate env ---
: "${APPLE_ID:?APPLE_ID is required for notarization}"
: "${APPLE_APP_SPECIFIC_PASSWORD:?APPLE_APP_SPECIFIC_PASSWORD is required for notarization}"

echo "=== Vapor Release Build ==="
echo "Repo:     $REPO_ROOT"
echo "Output:   $OUTPUT_DIR"
echo "Team ID:  $APPLE_TEAM_ID"
echo ""

mkdir -p "$OUTPUT_DIR" "$DERIVED_DATA"

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

# --- 4. Create DMG ---
echo "[3/6] Creating DMG..."
rm -f "$DMG_PATH"
hdiutil create \
  -volname "Vapor" \
  -srcfolder "$APP_PATH" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

# --- 5. Notarize ---
echo "[4/6] Submitting for notarization..."
xcrun notarytool submit "$DMG_PATH" \
  --apple-id "$APPLE_ID" \
  --password "$APPLE_APP_SPECIFIC_PASSWORD" \
  --team-id "$APPLE_TEAM_ID" \
  --wait

# --- 6. Staple ---
echo "[5/6] Stapling notarization ticket..."
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

# --- 7. SHA256 ---
echo "[6/6] Computing SHA256..."
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
