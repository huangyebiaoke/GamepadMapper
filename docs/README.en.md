# GamepadMapper — English

**GamepadMapper** is a macOS menu bar app that maps gamepad buttons and analog sticks to keyboard keys and mouse movements in real time.

<p align="center">
  <img src="../Assets/screenshot.png" alt="GamepadMapper Screenshot" width="600">
</p>

## Features

- Map any gamepad button to a keyboard key, mouse button, or mouse movement
- Real-time HID-level input for reliable background operation
- Multi-profile support — switch between different mappings instantly
- Per-profile sensitivity and deadzone configuration
- Multi-language UI: English, 简体中文, 日本語, 한국어, Русский, Español
- Live controller status visualization
- Debug log for troubleshooting

## Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon (M1+) or Intel Mac

## Build

```bash
git clone https://github.com/huangyebiaoke/GamepadMapper.git
cd GamepadMapper
swift build
```

## Usage

1. Launch the app — it appears as a gamepad icon in the menu bar
2. Connect your gamepad via Bluetooth or USB
3. Open Settings from the menu bar and click **Start Mapping**
4. Edit mappings to customize button-to-key assignments
5. Switch to any app — mapping works in the background

## Permissions

GamepadMapper requires **Accessibility** permission to send keyboard and mouse events system-wide. The app will guide you through granting permission on first launch.

---

[← Back to README](../README.md) · [License](../LICENSE)
