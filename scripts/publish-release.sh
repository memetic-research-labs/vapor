#!/usr/bin/env bash
# publish-release.sh
# Publishes a built Vapor DMG to GitHub Releases and bumps the Homebrew Cask.
#
# Usage:
#   scripts/publish-release.sh <dmg-path> <tag>
#
# Examples:
#   scripts/publish-release.sh dist/Vapor-1.0.8-8.dmg v1.0.8
#
# Prerequisites:
#   - gh CLI authenticated with push access to memetic-research-labs/vapor
#     and memetic-research-labs/homebrew-vapor
#   - DMG already built and notarized via scripts/build-release.sh
#
# The Cask stores the version as "<marketing>,<build>" and derives its download
# URL from that version, so only the version and sha256 lines are rewritten.

set -euo pipefail

VAPOR_REPO="memetic-research-labs/vapor"
TAP_REPO="memetic-research-labs/homebrew-vapor"
TAP_DIR=""

usage() {
  echo "Usage: scripts/publish-release.sh <dmg-path> <tag>"
  echo ""
  echo "Arguments:"
  echo "  dmg-path  Path to the built DMG (e.g. dist/Vapor-1.0.8-8.dmg)"
  echo "  tag       Git tag for the release (e.g. v1.0.8)"
  exit 1
}

cleanup() {
  if [ -n "$TAP_DIR" ] && [ -d "$TAP_DIR" ]; then
    rm -rf "$TAP_DIR"
  fi
}
trap cleanup EXIT

die() {
  echo "ERROR: $*" >&2
  exit 1
}

# --- Parse args ---
DMG_PATH="${1:-}"
TAG="${2:-}"

if [ -z "$DMG_PATH" ] || [ -z "$TAG" ]; then
  usage
fi

DMG_NAME="$(basename "$DMG_PATH")"

# Validate DMG name format: Vapor-<version>-<build>.dmg
if [[ ! "$DMG_NAME" =~ ^Vapor-[0-9]+\.[0-9]+\.[0-9]+-[0-9]+\.dmg$ ]]; then
  die "DMG name must match pattern Vapor-X.Y.Z-N.dmg (got: $DMG_NAME)"
fi

[ -f "$DMG_PATH" ] || die "DMG not found at $DMG_PATH"
DMG_PATH="$(cd "$(dirname "$DMG_PATH")" && pwd)/$DMG_NAME"

# --- Extract version components ---
# DMG_NAME: Vapor-1.0.8-8.dmg -> MARKETING_VERSION=1.0.8 BUILD_VERSION=8
VERSION_STR="${DMG_NAME#Vapor-}"
VERSION_STR="${VERSION_STR%.dmg}"
MARKETING_VERSION="${VERSION_STR%-*}"
BUILD_VERSION="${VERSION_STR##*-}"
CASK_VERSION="${MARKETING_VERSION},${BUILD_VERSION}"

# The tag must match the marketing version, otherwise the Cask would build a
# download URL pointing at a release that does not contain this DMG.
[ "$TAG" = "v${MARKETING_VERSION}" ] ||
  die "Tag $TAG does not match DMG marketing version $MARKETING_VERSION (expected v${MARKETING_VERSION})"

# --- Verify the DMG matches the app it claims to ship ---
command -v gh &> /dev/null || die "gh CLI is required. Install via: brew install gh"
gh auth status &> /dev/null || die "gh CLI is not authenticated. Run: gh auth login"

echo "Validating notarization..."
xcrun stapler validate "$DMG_PATH" > /dev/null ||
  die "DMG is not stapled/notarized: $DMG_PATH"

MOUNT_POINT="$(mktemp -d)"
hdiutil attach "$DMG_PATH" -mountpoint "$MOUNT_POINT" -nobrowse -quiet
APP_SHORT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$MOUNT_POINT/Vapor.app/Contents/Info.plist")"
APP_BUILD_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$MOUNT_POINT/Vapor.app/Contents/Info.plist")"
hdiutil detach "$MOUNT_POINT" -quiet
rmdir "$MOUNT_POINT"

[ "$APP_SHORT_VERSION" = "$MARKETING_VERSION" ] && [ "$APP_BUILD_VERSION" = "$BUILD_VERSION" ] ||
  die "DMG name says ${MARKETING_VERSION}-${BUILD_VERSION} but the app inside is ${APP_SHORT_VERSION}-${APP_BUILD_VERSION}"

# --- SHA256 (always written to disk so it can be uploaded) ---
SHASUM_PATH="${DMG_PATH%.dmg}.sha256"
if [ ! -f "$SHASUM_PATH" ]; then
  echo "No .sha256 file found; computing..."
  shasum -a 256 "$DMG_PATH" | awk '{print $1}' > "$SHASUM_PATH"
fi
SHA256="$(tr -d '[:space:]' < "$SHASUM_PATH")"

ACTUAL_SHA256="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
[ "$SHA256" = "$ACTUAL_SHA256" ] ||
  die "Recorded sha256 ($SHA256) does not match the DMG ($ACTUAL_SHA256)"

DOWNLOAD_URL="https://github.com/${VAPOR_REPO}/releases/download/${TAG}/${DMG_NAME}"

echo "=== Vapor Release Publisher ==="
echo "  Tag:       $TAG"
echo "  DMG:       $DMG_NAME"
echo "  Version:   $MARKETING_VERSION (build $BUILD_VERSION)"
echo "  Cask ver:  $CASK_VERSION"
echo "  SHA256:    $SHA256"
echo "  URL:       $DOWNLOAD_URL"
echo ""

# --- 1. Create GitHub Release ---
echo "[1/4] Creating GitHub Release $TAG..."

if gh release view "$TAG" --repo "$VAPOR_REPO" &> /dev/null; then
  echo "  Release $TAG already exists; uploading assets..."
  gh release upload "$TAG" "$DMG_PATH" "$SHASUM_PATH" --repo "$VAPOR_REPO" --clobber
else
  gh release create "$TAG" \
    --repo "$VAPOR_REPO" \
    --title "$TAG" \
    --generate-notes \
    "$DMG_PATH" "$SHASUM_PATH"
fi

echo "  Release published: https://github.com/${VAPOR_REPO}/releases/tag/${TAG}"
echo ""

# --- 2. Verify the published asset is downloadable and intact ---
echo "[2/4] Verifying published asset..."
REMOTE_SHA256="$(curl -fsSL "$DOWNLOAD_URL" | shasum -a 256 | awk '{print $1}')" ||
  die "Could not download $DOWNLOAD_URL"
[ "$REMOTE_SHA256" = "$SHA256" ] ||
  die "Published asset sha256 ($REMOTE_SHA256) does not match local DMG ($SHA256)"
echo "  Download URL serves the expected bytes."
echo ""

# --- 3. Bump Homebrew Cask via pull request ---
echo "[3/4] Bumping Homebrew Cask in $TAP_REPO..."

TAP_DIR="$(mktemp -d)/homebrew-vapor"
gh repo clone "$TAP_REPO" "$TAP_DIR" -- --quiet

CASK_FILE="$TAP_DIR/Casks/vapor.rb"
[ -f "$CASK_FILE" ] || die "Cask file not found in tap repo: $CASK_FILE"

# The URL is derived from the version, so it must stay interpolated.
grep -q 'version.csv.first' "$CASK_FILE" ||
  die "Cask no longer derives its URL from the version; update this script."

sed -i '' "s|^  version \".*\"|  version \"${CASK_VERSION}\"|" "$CASK_FILE"
sed -i '' "s|^  sha256 \".*\"|  sha256 \"${SHA256}\"|" "$CASK_FILE"

grep -q "^  version \"${CASK_VERSION}\"$" "$CASK_FILE" || die "Failed to update version in Cask"
grep -q "^  sha256 \"${SHA256}\"$" "$CASK_FILE" || die "Failed to update sha256 in Cask"
ruby -c "$CASK_FILE" > /dev/null || die "Cask has Ruby syntax errors after update"

echo "  Updated Casks/vapor.rb: version=$CASK_VERSION sha256=$SHA256"

cd "$TAP_DIR"

if git diff --quiet; then
  echo "  Cask already up to date; nothing to publish."
else
  BRANCH="bump-${TAG}-${BUILD_VERSION}"
  git switch -c "$BRANCH" --quiet
  git add Casks/vapor.rb
  git commit -m "Bump vapor to ${MARKETING_VERSION} build ${BUILD_VERSION}" --quiet
  git push -u origin "$BRANCH" --quiet

  gh pr create \
    --repo "$TAP_REPO" \
    --base main \
    --head "$BRANCH" \
    --title "Bump vapor to ${MARKETING_VERSION} build ${BUILD_VERSION}" \
    --body "Automated cask bump for [${TAG}](https://github.com/${VAPOR_REPO}/releases/tag/${TAG})."

  echo ""
  echo "  Waiting for cask install checks to register..."
  # `gh pr checks` cannot tell "not started yet" from "failed": both exit 1.
  # Wait for the run to appear before watching it, so a slow scheduler cannot
  # be mistaken for a failure after the release is already public.
  CHECKS_REGISTERED=""
  for _ in $(seq 1 30); do
    if [ "$(gh pr view "$BRANCH" --repo "$TAP_REPO" --json statusCheckRollup --jq '.statusCheckRollup | length')" -gt 0 ]; then
      CHECKS_REGISTERED="yes"
      break
    fi
    sleep 10
  done

  [ -n "$CHECKS_REGISTERED" ] ||
    die "Cask checks never started. Review $BRANCH in $TAP_REPO before merging."

  echo "  Waiting for cask install checks to finish..."
  gh pr checks "$BRANCH" --repo "$TAP_REPO" --watch --interval 15 ||
    die "Cask checks failed; the tap was not updated. Review the PR before merging."

  gh pr merge "$BRANCH" --repo "$TAP_REPO" --squash --delete-branch
  echo "  Cask merged into $TAP_REPO."
fi

echo ""

# --- 4. Done ---
echo "[4/4] Done!"
echo ""
echo "Install (the full token is required; 'vapor' alone resolves elsewhere):"
echo "  brew install --cask memetic-research-labs/vapor/vapor"
echo ""
echo "Upgrade existing installs:"
echo "  brew upgrade --cask memetic-research-labs/vapor/vapor"
echo ""
echo "Release:  https://github.com/${VAPOR_REPO}/releases/tag/${TAG}"
echo "Cask:     https://github.com/${TAP_REPO}/blob/main/Casks/vapor.rb"
