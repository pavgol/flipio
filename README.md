<div align="center">

<img src="App/Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png" width="160" alt="Flipio app icon" />

# Flipio

**Instantly fix mistyped text in the wrong keyboard layout.**

A lightweight macOS (sitting in Mac OS menu bar) app that converts selected text or the last typed word between keyboard layouts/languages with a single tap of the Option key. 

Modern open source Punto Switcher alternative for macOS.

[![macOS](https://img.shields.io/badge/macOS-14.0%2B-000000?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Homebrew](https://img.shields.io/badge/Homebrew-tap-FBB040?logo=homebrew&logoColor=white)](https://github.com/pggolub/homebrew-flipio)

</div>

---

## ✨ Features

- ⌨️ **Quick Layout Conversion** — Tap the Option key to convert selected text or the last typed word
- 🔄 **Bidirectional** — Auto-detects the layout and converts both ways (e.g., English ↔ Russian)
- 🧩 **System Integration** — Works with any macOS application
- 🪶 **Lightweight** — Runs quietly in your menu bar

## 📋 Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 15.0+ (for building from source)

## 📦 Installation

### Homebrew (recommended)

```bash
brew tap pggolub/flipio
brew install --cask flipio
```

> Flipio is ad-hoc signed (the author is not enrolled in the Apple Developer Program). The cask removes macOS's quarantine attribute after install so the app can launch without Gatekeeper warnings. Review the source before installing if that concerns you.

### Direct download (DMG)

Grab the latest `.dmg` from the [Releases page](https://github.com/pggolub/flipio/releases/latest), open it, and drag Flipio into `/Applications`.

Because the build is ad-hoc signed, macOS Gatekeeper will block it on first launch. Either right-click the app and choose **Open**, or strip the quarantine attribute manually:

```bash
xattr -dr com.apple.quarantine /Applications/Flipio.app
```

### From Source

1. Clone the repository:
   ```bash
   git clone https://github.com/pggolub/flipio.git
   cd flipio
   ```

2. Open the project in Xcode:
   ```bash
   open Flipio.xcodeproj
   ```

3. Build and run the project (⌘R)

4. Grant Accessibility permissions when prompted

## 🔍 Troubleshooting

Watch OS events with:

```bash
log stream --predicate 'subsystem == "com.flipio.app"' --level debug --style compact
```

## 🔒 Privacy

Flipio requires Accessibility permissions to:

- Monitor keyboard events for the Option key tap
- Read selected text for conversion
- Simulate keyboard input for converted text

All text processing happens locally on your device. **No data is sent to external servers.**

## 📄 License

MIT License — see [LICENSE](LICENSE) for details.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 💬 Support

If you encounter any issues or have feature requests, please [open an issue](https://github.com/pggolub/flipio/issues) on GitHub.
