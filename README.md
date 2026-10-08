<p align="center">
  <img src="assets/app-icon.png" alt="Download Organizer" width="128" height="128">
</p>

<h1 align="center">Download Organizer</h1>

<p align="center">
  <strong>Automatically organize your Downloads folder on macOS.</strong><br>
  Rules-based file sorting · Background monitoring · Full undo · Menu bar app
</p>

<p align="center">
  <a href="https://github.com/OWNER/REPO/releases/latest"><img src="https://img.shields.io/github/v/release/OWNER/REPO?style=flat-square&label=Download&color=6366f1" alt="Download latest"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-000?style=flat-square&logo=apple&logoColor=white" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-6-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift 6">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="MIT License"></a>
</p>

<p align="center">
  <img src="assets/screenshot.png" alt="Download Organizer screenshot" width="720">
</p>

---

## What it does

Download Organizer watches your Downloads folder (or any folder you choose) and sorts files into subfolders based on rules you define — file type, name patterns, size, dates, and more.

- **📂 Smart categories** — Built-in presets for Documents, Images, Videos, Archives, Music, Code, and more. Or create your own.
- **👁 Background monitoring** — Watches for new downloads and organizes them automatically.
- **↩️ Full undo** — Every move is tracked. Undo a single file or an entire batch.
- **🔍 Preview before moving** — See exactly what will happen before confirming.
- **📌 Menu bar** — Lives in your menu bar. Runs silently in the background.
- **🔒 Private** — No account. No network. No analytics. Everything stays on your Mac.

## Download

### DMG (recommended)

1. Go to the [**latest release**](https://github.com/OWNER/REPO/releases/latest)
2. Download `DownloadOrganizer-x.x.x.dmg`
3. Open the DMG and drag **Download Organizer** into your Applications folder
4. Launch from Applications

> **First launch:** macOS will show a security warning because the app is not notarized yet. To open it:
> - **Right-click** (or Control-click) the app → **Open** → click **Open** again
>
> Or run this once in Terminal:
> ```bash
> xattr -dr com.apple.quarantine "/Applications/Download Organizer.app"
> ```

### Homebrew (coming soon)

```bash
brew install --cask download-organizer
```

## How to use

1. **First launch** → Onboarding asks you to pick a folder (defaults to `~/Downloads`)
2. **Set up categories** → Use the built-in presets or create custom rules
3. **Preview** → Click "Preview" to see what will be moved and where
4. **Organize** → Confirm to move files, or enable background monitoring to do it automatically
5. **Undo** → Changed your mind? Undo any move from the Activity tab

## System requirements

| | Requirement |
|---|---|
| **macOS** | 14 (Sonoma) or later |
| **Chip** | Apple Silicon or Intel |
| **Storage** | ~15 MB |

## Building from source

Prerequisites: [Xcode 16+](https://developer.apple.com/xcode/) and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
# Install XcodeGen
brew install xcodegen

# Clone and build
git clone https://github.com/OWNER/REPO.git
cd DownloadOrganizer
xcodegen generate
xcodebuild -scheme DownloadOrganizer -destination 'platform=macOS' build
```

Or open the generated `DownloadOrganizer.xcodeproj` in Xcode and press ⌘R.

### Run tests

```bash
swift test --package-path Packages/DownloadOrganizerCore
```

## Project structure

```
DownloadOrganizer/
├── App/                          # SwiftUI app target (thin shell)
│   ├── UI/                       # Views, organized by feature
│   ├── Resources/                # Assets, localization
│   └── Support/                  # Info.plist, entitlements
├── Packages/DownloadOrganizerCore/
│   └── Sources/                  # All logic — testable without UI
│       ├── Domain/               # Models
│       ├── Rules/                # Rule engine, classification
│       ├── FileSystem/           # Scanner, organizer, conflict resolver
│       ├── Monitoring/           # FSEvents watcher, stability checker
│       └── History/              # Move history, undo
├── Scripts/                      # Build & release automation
└── .github/workflows/            # CI and release pipelines
```

All core logic lives in the `DownloadOrganizerCore` Swift package so it can be tested headlessly with `swift test`. The app target is a thin SwiftUI shell.

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Make sure tests pass (`swift test --package-path Packages/DownloadOrganizerCore`)
4. Open a Pull Request

## Privacy

Download Organizer is **completely offline**. It does not:
- Collect any data
- Make any network requests (except checking for updates, if enabled)
- Require any account or sign-in
- Read file contents — it only reads file metadata (name, size, dates, type)

Your files never leave your Mac.

## License

[MIT](LICENSE)

---

<p align="center">
  Made with ☕ for a cleaner Downloads folder.
</p>
