#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# Scripts/generate_appcast.sh — Generate Sparkle appcast.xml from releases
# ─────────────────────────────────────────────────────────────────────────────
#
# This script generates a Sparkle-compatible appcast.xml for the
# direct-distribution configuration. It can work in two modes:
#
#   1. With Sparkle's `generate_appcast` tool (preferred)
#   2. Manual XML generation from DMG files in build/releases/ (fallback)
#
# Environment variables:
#   SPARKLE_PRIVATE_KEY  — EdDSA private key for signing (base64, from generate_keys)
#   SPARKLE_KEY_FILE     — path to file containing the private key (alternative)
#   GITHUB_REPO_URL      — GitHub repo URL for download links
#                          (default: auto-detected via `gh` or git remote)
#
# The appcast points users at GitHub Releases download URLs so the DMG
# itself is the only thing hosted. Sparkle checks this feed for updates.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

RELEASES_DIR="$ROOT/build/releases"
APPCAST_FILE="$RELEASES_DIR/appcast.xml"

# Read version from project.yml
VERSION=$(grep 'MARKETING_VERSION:' project.yml | head -1 | sed 's/.*: *"\(.*\)"/\1/')
BUILD_NUMBER=$(grep 'CURRENT_PROJECT_VERSION:' project.yml | head -1 | sed 's/.*: *"\(.*\)"/\1/')
DMG_NAME="DownloadOrganizer-${VERSION}.dmg"
DMG_PATH="$RELEASES_DIR/$DMG_NAME"

# ── Resolve GitHub repo URL ─────────────────────────────────────────────────
if [ -z "${GITHUB_REPO_URL:-}" ]; then
  if command -v gh &>/dev/null; then
    GITHUB_REPO_URL="https://github.com/$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "")"
  fi
  if [ -z "${GITHUB_REPO_URL:-}" ] || [ "$GITHUB_REPO_URL" = "https://github.com/" ]; then
    GITHUB_REPO_URL=$(git remote get-url origin 2>/dev/null | sed 's/\.git$//' | sed 's|git@github.com:|https://github.com/|' || echo "")
  fi
  if [ -z "$GITHUB_REPO_URL" ]; then
    echo "⚠ Could not detect GitHub repo URL. Set GITHUB_REPO_URL env var."
    echo "  Appcast will use placeholder URLs."
    GITHUB_REPO_URL="https://github.com/OWNER/REPO"
  fi
fi

DOWNLOAD_URL="${GITHUB_REPO_URL}/releases/download/v${VERSION}/${DMG_NAME}"
APPCAST_URL="${GITHUB_REPO_URL}/releases/download/v${VERSION}/appcast.xml"

echo "▸ Generating appcast for v${VERSION}..."
echo "  Download URL: $DOWNLOAD_URL"

# ── Method 1: Try Sparkle's generate_appcast ─────────────────────────────────
SPARKLE_BIN=""
# Check common locations for generate_appcast
for candidate in \
  "$ROOT/Packages/DownloadOrganizerCore/.build/artifacts/sparkle/Sparkle/bin/generate_appcast" \
  "$HOME/Library/Developer/Xcode/DerivedData/*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast" \
  "/usr/local/bin/generate_appcast" \
  "$(brew --prefix 2>/dev/null)/bin/generate_appcast"; do
  # Handle glob expansion
  for expanded in $candidate; do
    if [ -x "$expanded" ]; then
      SPARKLE_BIN="$expanded"
      break 2
    fi
  done
done

if [ -n "$SPARKLE_BIN" ] && [ -n "${SPARKLE_PRIVATE_KEY:-}" ]; then
  echo "  Using Sparkle's generate_appcast: $SPARKLE_BIN"

  export SPARKLE_PRIVATE_KEY
  "$SPARKLE_BIN" \
    --download-url-prefix "${GITHUB_REPO_URL}/releases/download/v${VERSION}/" \
    "$RELEASES_DIR"

  echo "  ✓ Appcast generated via Sparkle tooling"
  exit 0
fi

# ── Method 2: Manual appcast generation ──────────────────────────────────────
echo "  Using manual appcast generation (Sparkle generate_appcast not available)"

if [ ! -f "$DMG_PATH" ]; then
  echo "  ✗ DMG not found at $DMG_PATH — run release.sh first"
  exit 1
fi

# Compute file size and signature
FILE_SIZE=$(stat -f%z "$DMG_PATH" 2>/dev/null || stat --printf="%s" "$DMG_PATH" 2>/dev/null)
PUB_DATE=$(date -R 2>/dev/null || date "+%a, %d %b %Y %H:%M:%S %z")

# EdDSA signature (if key available)
EDDSA_SIGNATURE=""
if [ -n "${SPARKLE_PRIVATE_KEY:-}" ]; then
  # Sign using Sparkle's sign_update if available
  SIGN_BIN=""
  for candidate in \
    "$ROOT/Packages/DownloadOrganizerCore/.build/artifacts/sparkle/Sparkle/bin/sign_update" \
    "$HOME/Library/Developer/Xcode/DerivedData/*/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update" \
    "/usr/local/bin/sign_update"; do
    for expanded in $candidate; do
      if [ -x "$expanded" ]; then
        SIGN_BIN="$expanded"
        break 2
      fi
    done
  done

  if [ -n "$SIGN_BIN" ]; then
    EDDSA_SIGNATURE=$(echo "$SPARKLE_PRIVATE_KEY" | "$SIGN_BIN" --ed-key-file - "$DMG_PATH" 2>/dev/null || echo "")
  fi
elif [ -n "${SPARKLE_KEY_FILE:-}" ] && [ -f "${SPARKLE_KEY_FILE}" ]; then
  if [ -n "$SIGN_BIN" ]; then
    EDDSA_SIGNATURE=$("$SIGN_BIN" --ed-key-file "$SPARKLE_KEY_FILE" "$DMG_PATH" 2>/dev/null || echo "")
  fi
fi

# Build the enclosure attributes
ENCLOSURE_ATTRS="url=\"${DOWNLOAD_URL}\" sparkle:version=\"${BUILD_NUMBER}\" sparkle:shortVersionString=\"${VERSION}\" length=\"${FILE_SIZE}\" type=\"application/octet-stream\""

if [ -n "$EDDSA_SIGNATURE" ]; then
  ENCLOSURE_ATTRS+=" sparkle:edSignature=\"${EDDSA_SIGNATURE}\""
fi

# Generate appcast XML
cat > "$APPCAST_FILE" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Download Organizer</title>
    <link>${APPCAST_URL}</link>
    <description>Download Organizer update feed</description>
    <language>en</language>

    <item>
      <title>Version ${VERSION}</title>
      <pubDate>${PUB_DATE}</pubDate>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <enclosure ${ENCLOSURE_ATTRS} />
    </item>

  </channel>
</rss>
XML

echo "  ✓ Appcast written to $APPCAST_FILE"

# Warn if no signature
if [ -z "$EDDSA_SIGNATURE" ]; then
  echo ""
  echo "  ⚠ WARNING: Appcast was generated WITHOUT an EdDSA signature."
  echo "    Sparkle will reject unsigned updates in production."
  echo "    Set SPARKLE_PRIVATE_KEY or SPARKLE_KEY_FILE to sign."
  echo ""
  echo "    To generate keys, run Sparkle's generate_keys:"
  echo "      .build/artifacts/sparkle/Sparkle/bin/generate_keys"
fi
