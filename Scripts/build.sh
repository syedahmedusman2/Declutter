#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

xcodegen generate

xcodebuild \
  -project DownloadOrganizer.xcodeproj \
  -scheme DownloadOrganizer \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$ROOT/build/DerivedData" \
  build

swift test --package-path Packages/DownloadOrganizerCore
