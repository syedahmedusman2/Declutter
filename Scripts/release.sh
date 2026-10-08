#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# Scripts/release.sh — Build, sign, package, and optionally release
# ─────────────────────────────────────────────────────────────────────────────
#
# Usage:
#   ./Scripts/release.sh                     # ad-hoc signed build (no Apple Developer account)
#   ./Scripts/release.sh --notarize          # Developer ID signed + notarized (requires paid account)
#   ./Scripts/release.sh --github            # also create a GitHub release (requires `gh` CLI)
#   ./Scripts/release.sh --notarize --github # full pipeline
#
# Environment variables (all optional for ad-hoc; required for --notarize):
#   CODESIGN_IDENTITY       — "Developer ID Application: Name (TEAMID)" (default: "-" for ad-hoc)
#   NOTARY_PROFILE          — keychain profile name for notarytool (default: "AC_NOTARY")
#   SPARKLE_PRIVATE_KEY     — Sparkle EdDSA private key for signing the update archive
#   SPARKLE_KEY_FILE        — path to file containing the Sparkle private key (alternative)
#
# Prerequisites:
#   brew install xcodegen create-dmg
#   (optional) brew install gh               # for --github flag
#   (optional) Sparkle's generate_appcast    # for appcast generation
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Parse flags ──────────────────────────────────────────────────────────────
DO_NOTARIZE=false
DO_GITHUB=false
for arg in "$@"; do
  case "$arg" in
    --notarize) DO_NOTARIZE=true ;;
    --github)   DO_GITHUB=true ;;
    --help|-h)
      head -20 "$0" | grep '^#' | sed 's/^# \?//'
      exit 0 ;;
    *) echo "Unknown flag: $arg"; exit 1 ;;
  esac
done

# ── Resolve paths ────────────────────────────────────────────────────────────
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BUILD_DIR="$ROOT/build"
ARCHIVE_PATH="$BUILD_DIR/App.xcarchive"
EXPORT_DIR="$BUILD_DIR/Export"
RELEASES_DIR="$BUILD_DIR/releases"
DERIVED_DATA="$BUILD_DIR/DerivedData"

APP_NAME="Declutter"
SCHEME="Declutter"
CONFIGURATION="Release-Direct"

# Read version from project.yml
VERSION=$(grep 'MARKETING_VERSION:' project.yml | head -1 | sed 's/.*: *"\(.*\)"/\1/')
BUILD_NUMBER=$(grep 'CURRENT_PROJECT_VERSION:' project.yml | head -1 | sed 's/.*: *"\(.*\)"/\1/')
DMG_NAME="Declutter-${VERSION}.dmg"

CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"  # "-" = ad-hoc
NOTARY_PROFILE="${NOTARY_PROFILE:-AC_NOTARY}"

echo "═══════════════════════════════════════════════════════════"
echo "  Declutter — Release v${VERSION} (build ${BUILD_NUMBER})"
echo "  Identity: ${CODESIGN_IDENTITY}"
echo "  Notarize: ${DO_NOTARIZE}"
echo "  GitHub:   ${DO_GITHUB}"
echo "═══════════════════════════════════════════════════════════"

# ── Step 0: Clean ────────────────────────────────────────────────────────────
echo ""
echo "▸ Cleaning previous build artifacts..."
rm -rf "$ARCHIVE_PATH" "$EXPORT_DIR"
mkdir -p "$RELEASES_DIR"

# ── Step 1: Generate Xcode project ──────────────────────────────────────────
echo ""
echo "▸ Step 1/9: Generating Xcode project..."
xcodegen generate --quiet

# ── Step 2: Archive ─────────────────────────────────────────────────────────
echo ""
echo "▸ Step 2/9: Archiving ($CONFIGURATION)..."

# If Release-Direct config doesn't exist yet, fall back to Release
if ! xcodebuild -project Declutter.xcodeproj -scheme "$SCHEME" -showBuildSettings -configuration "$CONFIGURATION" &>/dev/null 2>&1; then
  echo "  ⚠ Configuration '$CONFIGURATION' not found, falling back to 'Release'"
  CONFIGURATION="Release"
fi

xcodebuild archive \
  -project Declutter.xcodeproj \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -archivePath "$ARCHIVE_PATH" \
  -derivedDataPath "$DERIVED_DATA" \
  -destination 'generic/platform=macOS' \
  CODE_SIGN_IDENTITY="$CODESIGN_IDENTITY" \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  ONLY_ACTIVE_ARCH=NO \
  | tail -5

echo "  ✓ Archive created at $ARCHIVE_PATH"

# ── Step 3: Export ──────────────────────────────────────────────────────────
echo ""
echo "▸ Step 3/9: Exporting archive..."

# Determine export method
if [ "$CODESIGN_IDENTITY" = "-" ]; then
  EXPORT_METHOD="mac-application"
else
  EXPORT_METHOD="developer-id"
fi

# Generate ExportOptions.plist
EXPORT_OPTIONS="$BUILD_DIR/ExportOptions.plist"
cat > "$EXPORT_OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>${EXPORT_METHOD}</string>
    <key>destination</key>
    <string>export</string>
</dict>
</plist>
PLIST

# For ad-hoc builds, we extract the app directly from the archive
if [ "$CODESIGN_IDENTITY" = "-" ]; then
  mkdir -p "$EXPORT_DIR"
  cp -R "$ARCHIVE_PATH/Products/Applications/$APP_NAME.app" "$EXPORT_DIR/"
  echo "  ✓ Extracted app (ad-hoc signed)"
else
  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    -exportPath "$EXPORT_DIR" \
    | tail -3
  echo "  ✓ Exported with method: $EXPORT_METHOD"
fi

APP_PATH="$EXPORT_DIR/$APP_NAME.app"

if [ ! -d "$APP_PATH" ]; then
  echo "  ✗ ERROR: App not found at $APP_PATH"
  exit 1
fi

# ── Step 4: Create zip for notarization ─────────────────────────────────────
echo ""
echo "▸ Step 4/9: Creating zip archive..."
APP_ZIP="$BUILD_DIR/$APP_NAME.zip"
rm -f "$APP_ZIP"
ditto -c -k --keepParent "$APP_PATH" "$APP_ZIP"
echo "  ✓ Zip: $APP_ZIP ($(du -h "$APP_ZIP" | cut -f1))"

# ── Step 5: Notarize (only with --notarize) ─────────────────────────────────
if [ "$DO_NOTARIZE" = true ]; then
  if [ "$CODESIGN_IDENTITY" = "-" ]; then
    echo ""
    echo "  ✗ ERROR: Cannot notarize an ad-hoc signed build."
    echo "    Set CODESIGN_IDENTITY to your Developer ID certificate."
    exit 1
  fi

  echo ""
  echo "▸ Step 5/9: Submitting for notarization..."
  xcrun notarytool submit "$APP_ZIP" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

  echo ""
  echo "▸ Step 6/9: Stapling notarization ticket..."
  xcrun stapler staple "$APP_PATH"
  echo "  ✓ App stapled"
else
  echo ""
  echo "▸ Step 5–6/9: Skipping notarization (use --notarize to enable)"
fi

# ── Step 7: Create DMG ──────────────────────────────────────────────────────
echo ""
echo "▸ Step 7/9: Creating DMG..."
DMG_PATH="$RELEASES_DIR/$DMG_NAME"
rm -f "$DMG_PATH"

create-dmg \
  --volname "$APP_NAME" \
  --volicon "$APP_PATH/Contents/Resources/AppIcon.icns" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "$APP_NAME.app" 175 190 \
  --app-drop-link 425 190 \
  --hide-extension "$APP_NAME.app" \
  "$DMG_PATH" \
  "$APP_PATH" \
  2>&1 || true  # create-dmg returns non-zero if no icon found; that's okay

if [ ! -f "$DMG_PATH" ]; then
  # Fallback: create a simple DMG without fancy layout
  echo "  ⚠ Fancy DMG failed, creating simple DMG..."
  hdiutil create -volname "$APP_NAME" \
    -srcfolder "$APP_PATH" \
    -ov -format UDZO \
    "$DMG_PATH"
fi

echo "  ✓ DMG: $DMG_PATH ($(du -h "$DMG_PATH" | cut -f1))"

# ── Step 8: Sign and notarize DMG ───────────────────────────────────────────
if [ "$CODESIGN_IDENTITY" != "-" ]; then
  echo ""
  echo "▸ Step 8/9: Signing DMG..."
  codesign --force --sign "$CODESIGN_IDENTITY" --timestamp "$DMG_PATH"
  echo "  ✓ DMG signed"

  if [ "$DO_NOTARIZE" = true ]; then
    echo "  Notarizing DMG..."
    xcrun notarytool submit "$DMG_PATH" \
      --keychain-profile "$NOTARY_PROFILE" \
      --wait
    xcrun stapler staple "$DMG_PATH"
    echo "  ✓ DMG notarized and stapled"
  fi
else
  echo ""
  echo "▸ Step 8/9: Skipping DMG signing (ad-hoc build)"
fi

# ── Step 9: Generate Sparkle appcast ────────────────────────────────────────
echo ""
echo "▸ Step 9/9: Generating appcast..."
"$ROOT/Scripts/generate_appcast.sh" || echo "  ⚠ Appcast generation skipped (see above)"

# ── Optional: GitHub release ────────────────────────────────────────────────
if [ "$DO_GITHUB" = true ]; then
  echo ""
  echo "▸ Creating GitHub release v${VERSION}..."

  if ! command -v gh &>/dev/null; then
    echo "  ✗ ERROR: 'gh' CLI not installed. Run: brew install gh"
    exit 1
  fi

  CHANGELOG=""
  if [ -f "$ROOT/CHANGELOG.md" ]; then
    # Extract the section for this version
    CHANGELOG=$(awk "/^## .*${VERSION}/,/^## /" "$ROOT/CHANGELOG.md" | head -n -1)
  fi

  RELEASE_NOTES="## Declutter v${VERSION}

### Installation

1. Download \`${DMG_NAME}\` below
2. Open the DMG and drag **Declutter** to your Applications folder
3. Launch from Applications"

  if [ "$CODESIGN_IDENTITY" = "-" ]; then
    RELEASE_NOTES+="
4. **First launch**: Right-click the app → Open, or run:
   \`\`\`bash
   xattr -dr com.apple.quarantine /Applications/Declutter.app
   \`\`\`

> ⚠️ This build is ad-hoc signed (not notarized). macOS Gatekeeper will show a warning on first launch. Use the steps above to bypass it."
  fi

  if [ -n "$CHANGELOG" ]; then
    RELEASE_NOTES+="

### Changes
${CHANGELOG}"
  fi

  RELEASE_FILES=("$DMG_PATH")

  # Include appcast if it exists
  APPCAST="$RELEASES_DIR/appcast.xml"
  if [ -f "$APPCAST" ]; then
    RELEASE_FILES+=("$APPCAST")
  fi

  # Include zip for direct download
  RELEASE_FILES+=("$APP_ZIP")

  gh release create "v${VERSION}" \
    --title "v${VERSION}" \
    --notes "$RELEASE_NOTES" \
    --draft \
    "${RELEASE_FILES[@]}"

  echo "  ✓ Draft release created: v${VERSION}"
  echo "    Review at: https://github.com/$(gh repo view --json nameWithOwner -q .nameWithOwner)/releases"
fi

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  ✓ Release v${VERSION} build complete!"
echo ""
echo "  Artifacts:"
echo "    DMG : $DMG_PATH"
echo "    ZIP : $APP_ZIP"
[ -f "$RELEASES_DIR/appcast.xml" ] && echo "    Feed: $RELEASES_DIR/appcast.xml"
echo ""
if [ "$CODESIGN_IDENTITY" = "-" ]; then
  echo "  ⚠ This is an AD-HOC build (no Developer ID)."
  echo "    Recipients must right-click → Open or run:"
  echo "    xattr -dr com.apple.quarantine /Applications/Declutter.app"
fi
echo "═══════════════════════════════════════════════════════════"
