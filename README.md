# CleanBar 👁️✨

**CleanBar** is a lightweight, open-source macOS menu bar manager designed to declutter and organize status bar icons effortlessly.

![macOS 13+](https://img.shields.io/badge/macOS-13.0%2B-blue?style=flat-square&logo=apple)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange?style=flat-square&logo=swift)
![License MIT](https://img.shields.io/badge/License-MIT-green?style=flat-square)

---

## Features

- 👁️ **Single Unified Status Icon**: A clean Eye icon acts as the single controller for your menu bar.
- 🖱️ **Hover-to-Reveal**: Simply move your mouse over the top menu bar to instantly reveal hidden icons.
- 🎛️ **Click-Away Preferences Popover**: Left-click the Eye icon to launch preferences; clicks outside dismiss the window automatically.
- 🚀 **Native Launch at Login**: Modern `SMAppService` login item management with automatic `/Applications` folder validation.
- 💻 **Hardware Notch Avoidance**: Smart layout engine that prevents status items from hiding behind physical notch hardware.
- 📦 **App Store Ready**: Includes App Store Connect encryption compliance (`ITSAppUsesNonExemptEncryption`).

---

## How It Works

1. **Grant Accessibility Access**: CleanBar requires Accessibility permissions to monitor mouse movement over the top menu bar.
2. **Organize Icons**: Hold `⌘ Command` and drag any third-party menu bar icon to the **left** of CleanBar's Eye icon to hide it.
3. **Hover to Expand**: Move your cursor over the menu bar space to reveal all hidden icons seamlessly.

---

## Requirements

- **Operating System**: macOS 13.0 (Ventura) or later.
- **Development Toolchain**: Xcode 15.0+ or Swift 5.9 toolchain.

---

## Building & Running

### Using Xcode
```bash
git clone https://github.com/AlainL88/CleanBar.git
cd CleanBar
open CleanBar.xcodeproj
```
Select the **CleanBar** scheme and hit `Cmd + R` to build and run.

### Using Swift Package Manager / CLI
```bash
swift build -c release
swift test
```

---

## License

This project is open-source under the [MIT License](LICENSE).
