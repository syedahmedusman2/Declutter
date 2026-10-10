# Changelog

All notable changes to Declutter will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.1] - 2026-10-11

### Fixed
- App freeze / beachball on first launch after allowing the download in Privacy & Security
- Menu bar icon update loop that could peg the CPU and crash the app during scene setup

### Changed
- Settings writes now skip no-op updates to keep launch and background mode lighter

## [0.1.0] - 2026-10-09

### Added
- Initial release
- Rules-based file organization with customizable categories
- Built-in presets for Documents, Images, Videos, Archives, Music, and Code
- Background monitoring via FSEvents
- Full undo support for all file moves
- Preview mode to see planned moves before confirming
- Menu bar app with quick status and controls
- Onboarding wizard for first-time setup
- Security-scoped bookmarks for sandboxed folder access
- Sparkle auto-updates (direct distribution builds)
