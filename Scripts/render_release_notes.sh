#!/bin/bash
# Print GitHub release notes for one version to stdout.
#
# Usage:
#   render_release_notes.sh <version> <dmg-path> <ad-hoc|developer-id>
#
# Changelog text comes from the Keep a Changelog section "## [<version>]".
# macOS awk treats a range as one line when the start line also matches the
# end pattern, and BSD head does not accept "head -n -1", so this walks the
# file itself and stops before the next heading.
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <version> <dmg-path> <ad-hoc|developer-id>" >&2
  exit 2
fi

VERSION="$1"
DMG_PATH="$2"
SIGNING_MODE="$3"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHANGELOG_FILE="${CHANGELOG_FILE:-$ROOT/CHANGELOG.md}"

if [ ! -f "$DMG_PATH" ]; then
  echo "DMG not found: $DMG_PATH" >&2
  exit 1
fi

DMG_NAME="$(basename "$DMG_PATH")"
DMG_SIZE="$(du -h "$DMG_PATH" | cut -f1)"
DMG_SHA="$(shasum -a 256 "$DMG_PATH" | cut -d' ' -f1)"

echo "## Declutter v${VERSION}"
echo

if [ -f "$CHANGELOG_FILE" ]; then
  CHANGES="$(
    awk -v version="$VERSION" '
      BEGIN {
        esc = version
        gsub(/\./, "\\.", esc)
        header = "^## \\[" esc "\\]"
      }
      $0 ~ header { printing = 1; next }
      printing && /^## / { exit }
      printing {
        if (!started && $0 ~ /^[[:space:]]*$/) next
        started = 1
        print
      }
    ' "$CHANGELOG_FILE"
  )"
  if [ -n "$CHANGES" ]; then
    printf '%s\n\n' "$CHANGES"
  fi
fi

cat <<EOF
### Installation

1. Download \`${DMG_NAME}\` (${DMG_SIZE})
2. Double-click the downloaded file to open it
EOF

if [ "$SIGNING_MODE" = "developer-id" ]; then
  cat <<'EOF'
3. Drag **Declutter** onto **Applications**
4. Open the **Applications** folder and double-click **Declutter**

This build is **signed with Developer ID** and **notarized by Apple**. macOS will open it without any warnings.
EOF
else
  cat <<'EOF'
3. If your Mac says Apple could not verify “Declutter”:
   1. Click **Done**
   2. Click the Apple menu () in the top-left corner → **System Settings**
   3. Click **Privacy & Security**
   4. Scroll down until you see **“Declutter” was blocked**
   5. Click **Open Anyway**
   6. Use Touch ID, or type your Mac password, and click **Open Anyway** again
4. A window opens. Drag **Declutter** onto **Applications**
5. Open the **Applications** folder and double-click **Declutter**
6. If the same message appears, go back to **Privacy & Security** and click **Open Anyway** again

You only need to do this the first time. After that, open Declutter from Applications as usual.

> [!NOTE]
> This build is not notarized by Apple yet. That is normal for open-source software without a paid Apple Developer certificate. Declutter does not phone home — your files stay on your Mac.
EOF
fi

cat <<EOF

### Checksums

| File | SHA-256 |
|------|---------|
| \`${DMG_NAME}\` | \`${DMG_SHA}\` |

### System Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon or Intel Mac
EOF
