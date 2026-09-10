# BendMac

A softer side of your Mac. A free, open-source desktop effect that gently blurs as you close your MacBook lid.

Inspired by [Bendy](https://trybendy.app/) and the folding-screen animation that inspired it. BendMac is an independent implementation, not affiliated with Bendy or Apple.

[Download for Mac](https://github.com/IuCC123/BendMac/releases/latest) · [Contribute](CONTRIBUTING.md) · [Report an issue](https://github.com/IuCC123/BendMac/issues)

## The effect

The desktop stays nearly flat while a progressive Gaussian blur gathers near the top. The bottom remains sharp and anchored. Opening the lid clears the effect smoothly. Choose Silk, Shade, or Frost and adjust the perspective, blur, shadow, and clear angle.

The software tilt is capped at 12°, with 7.8° at the default setting. The physical lid supplies the rest of the movement. Escape pauses the effect while it is visible. Closing Settings leaves the app in the menu bar.

## Requirements

- macOS 14 Sonoma or later.
- Apple silicon MacBook with a lid-angle sensor. Tested on an M5 MacBook Air. Other models need community testing.
- Screen Recording permission for the live desktop effect. The preview works without it.

Only the built-in screen bends. External displays are unchanged. Sleep and display changes pause the effect.

## Install

1. Download and unzip the latest release.
2. Move BendMac to Applications and open it.
3. Choose **General → Enable desktop effect**.
4. Allow BendMac in **System Settings → Privacy & Security → Screen & System Audio Recording**. Relaunch if macOS requests it.

This early release is signed ad hoc, not Developer ID signed or notarized. macOS may require approval in Privacy & Security. You can also inspect and build the source yourself.

No login item is installed. Quit from the BendMac menu-bar menu to stop the app.

## Build

Open `BendMac.xcodeproj` in Xcode, choose the BendMac scheme and My Mac, then Run. The project requires Apple's Metal compiler component. Xcode may offer to install it, or use `xcodebuild -downloadComponent MetalToolchain` if supported by your Xcode version.

To regenerate the project, install XcodeGen and run:

```sh
./scripts/build.sh
```

Output: `build/Build/Products/Release/BendMac.app`.

## How it works

- SwiftUI settings and AppKit menu-bar/window lifecycle.
- ScreenCaptureKit captures the built-in desktop while excluding BendMac, preventing recursive capture. Audio capture is disabled.
- Metal applies a restrained bottom-anchored perspective transform.
- Metal Performance Shaders creates 10 / 28 / 64 px Gaussian bands at an 880 px reference width. The blur grows toward the top.
- IOKit reads the lid-angle HID feature report without root, a driver, or Accessibility permission. The transport API is public, but Apple's report format is undocumented and may change.
- Sensor reads run at 60 Hz while enabled and 4 Hz while paused. Capture requests 5 fps while flat and 60 fps while bending. The overlay stops rendering when flat.
- Carbon registers Escape only while the effect is visible.

Frames remain in memory. BendMac does not save recordings or upload screen content. The overlay passes pointer input through to the desktop without remapping coordinates.

## Verify

```sh
./scripts/verify.sh
```

This checks lid thresholds, monotonic progress, refresh-rate-independent smoothing, and reversal; verifies signing; reads the sensor; and renders a fold/unfold sequence through the compiled Metal pipeline. FFmpeg is optional for producing the preview video.

The app also supports `--smoke` for a three-second live capture test. It requires Screen Recording permission, applies a manual 42° angle, writes frame-count/overlay/sensor diagnostics to `/tmp/bendmac-smoke.txt`, then pauses. It saves no screen images.

## Website

The landing page source is in `website/dist`. It uses HTML, CSS, and a small JavaScript controller for the video preview. No build step or third-party runtime is needed.

```sh
python3 -m http.server 4873 --directory website/dist
```

## Contributing and license

Bug reports, hardware compatibility reports, animation improvements, and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

Released under the [MIT license](LICENSE). Please retain attribution to Bendy when describing the inspiration. The reference videos and Bendy's assets are not included in this repository.
