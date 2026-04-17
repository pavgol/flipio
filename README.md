# Flipio

A macOS menu bar app that instantly converts text between keyboard layouts. Perfect for when you accidentally type in the wrong keyboard layout.

## Features

- **Quick Layout Conversion**: Tap the Option key to convert selected text or the last typed word between keyboard layouts
- **Bidirectional**: Automatically detects the layout and converts both ways (e.g., English ↔ Russian)
- **Two Conversion Modes**:
  - **Selection Mode**: Select text and tap Option to convert it
  - **Typed Word Mode**: Just tap Option after typing to convert the last word
- **Multiple Conversions**: Keep tapping Option to toggle back and forth between layouts
- **System Integration**: Works with any macOS application
- **Launch at Login**: Optional auto-start on system startup
- **Lightweight**: Runs quietly in your menu bar

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 15.0+ (for building from source)

## Installation

### Homebrew (recommended)

```bash
brew tap pavel-golub/flipio
brew install --cask flipio
```

Flipio is ad-hoc signed (the author is not enrolled in the Apple Developer Program). The cask removes macOS's quarantine attribute after install so the app can launch without Gatekeeper warnings. Review the source before installing if that concerns you.

### From Source

1. Clone the repository:
   ```bash
   git clone https://github.com/pavel-golub/flipio.git
   cd flipio
   ```

2. Open the project in Xcode:
   ```bash
   open Flipio.xcodeproj
   ```

3. Build and run the project (⌘R)

4. Grant Accessibility permissions when prompted

## Troubleshooting
Watch OS events using

```bash
log stream --predicate 'subsystem == "com.flipio.app"' --level debug --style compact
```

## Privacy

Flipio requires Accessibility permissions to:
- Monitor keyboard events for the Option key tap
- Read selected text for conversion
- Simulate keyboard input for converted text

All text processing happens locally on your device. No data is sent to external servers.

## License

MIT License - see [LICENSE](LICENSE) for details

## Author

Pavel Golub

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Support

If you encounter any issues or have feature requests, please open an issue on GitHub.
