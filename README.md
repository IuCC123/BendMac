# BendMac

[![BendMac folding and blurring the desktop as the lid closes](docs/demo.gif)](https://bendmac.app/assets/bend-preview.mp4)

[Website](https://bendmac.app) · [Watch the full demo](https://bendmac.app/assets/bend-preview.mp4) · [Download for Mac](https://github.com/IuCC123/BendMac/releases/latest/download/BendMac-macOS.dmg)

BendMac makes your desktop bend and blur as you close your MacBook. Open the lid and it settles back into place. It's free, open source, and lives in the menu bar.

Inspired by [Bendy](https://trybendy.app/) and the iPhone Duo folding animation. This is an independent implementation, with no affiliation to Bendy or Apple.

## Getting started

You'll need macOS 14 or later and an Apple silicon MacBook with a lid-angle sensor. So far, it's been tested on an M5 MacBook Air. Reports from other models are welcome.

1. Download and open the DMG, then drag BendMac onto the Applications folder.
2. Open BendMac and choose **General → Enable desktop effect**.
3. Allow it in **System Settings → Privacy & Security → Screen & System Audio Recording**. Relaunch if macOS asks you to.

The current release is signed ad hoc and isn't notarized, so macOS may ask you to approve it in Privacy & Security. You can also build it yourself.

Settings has a preview you can try without screen recording permission. You can adjust the blur, perspective, shadow, and angle at which the effect clears. Press Escape while the effect is visible to pause it. Closing Settings leaves BendMac running; quit from its menu-bar menu.

Only the built-in display is affected. BendMac pauses for sleep or display changes and doesn't add itself to your login items.

## Updates

From version 0.4.0, BendMac can download and install updates in the app. Use **Check for updates** in the sidebar or menu bar. Sparkle verifies each update before installing it. If you have an older version, download the new app manually once.

## Privacy

ScreenCaptureKit supplies the desktop frames for the effect. They stay in memory: BendMac doesn't save recordings, capture audio, or upload screen content. Its own windows are excluded from capture so the effect doesn't feed back into itself.

## Building

Open `BendMac.xcodeproj` in Xcode, select the BendMac scheme and My Mac, then run it. You'll need Apple's Metal compiler component; Xcode can prompt you to install it.

If you have XcodeGen installed, you can regenerate the project and build from the terminal:

```sh
./scripts/build.sh
```

The app will be in `build/Build/Products/Release/BendMac.app`.

After building, run the checks with:

```sh
./scripts/verify.sh
```

This tests the motion math, checks the app signature, reads the lid sensor, and renders a preview through Metal. FFmpeg is optional if you also want a preview video. These checks don't replace testing with a real lid.

## Working on it

The app uses SwiftUI for settings, AppKit for the menu bar and overlay, and Metal for the effect. IOKit reads the lid sensor through an undocumented HID report, so support may vary between hardware and macOS versions.

Bug fixes, animation tweaks, and hardware reports are all welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for how to get started, or [open an issue](https://github.com/IuCC123/BendMac/issues) if something isn't working.

The landing page lives in `website/dist` and needs no build step. To run it locally:

```sh
python3 -m http.server 4873 --directory website/dist
```

BendMac is released under the [MIT license](LICENSE). Bendy's assets and the reference videos aren't included in this repository.
