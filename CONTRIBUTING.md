# Contributing to BendMac

BendMac is free and open source. Contributions are welcome, including small fixes and reports from different MacBook models.

## Report a problem

Open an issue with your MacBook model, macOS version, BendMac version, and steps to reproduce it. For animation feedback, describe the lid position and your perspective/blur/shadow settings. Never include private desktop content, credentials, or hardware serial numbers.

## Send a change

1. Fork the repository and create a branch.
2. Open `BendMac.xcodeproj` in Xcode or use `scripts/build.sh`.
3. Keep the change focused and explain what it fixes. Format Swift files with `xcrun swift-format format --in-place --recursive BendMac Tests scripts`.
4. Run `scripts/verify.sh` for animation, lifecycle, or sensor changes. This includes `scripts/verify-lifecycle.sh`, which tests the real app model with controlled sensor/capture failures and isolated preferences, without displaying an overlay. For capture or startup changes, also run `scripts/verify-capture.sh` on a logged-in Mac with Screen Recording permission. This briefly displays a magenta test square. It checks safe startup without visible windows and verifies that a colored overlay stays out of captured frames across reconnects; it saves no screen content. For full effect lifecycle changes, run `scripts/verify-live-effect.sh` after building: it briefly bends and clears the desktop three times using isolated settings, and checks that pausing clears frames and stops the model timer. Test on a real Mac when possible and say what you could not verify.
5. Open a pull request with the relevant validation results.

## Design and implementation

The effect should feel restrained. The physical hinge supplies the rotation; software lifts the content, draws the upper sides inward, and adds progressive blur and subtle shading. Keep the bottom edge anchored and the animation reversible.

Use native macOS frameworks. Do not introduce screen-content uploads, persistent recordings, root requirements, or Accessibility-based automation. Changes to sensor access need clear hardware/OS compatibility notes because the HID report is undocumented.

Preserve keyboard access and reduced-motion behavior. Keep the landing page's Bendy attribution. Use public, shareable test content in demonstrations.

## License

Contributions are distributed under the repository's MIT license. Include appropriate attribution for any third-party code or assets you add.
