# Publishing an update

BendMac uses Sparkle 2 for in-app updates. The app reads `docs/appcast.xml` from this repository and downloads signed archives from GitHub Releases.

## Signing key

The private update-signing key is stored in the macOS login Keychain under the Sparkle account `BendMac`. The public key is in `project.yml`. Keep a secure backup of the private key outside this repository. Losing it would prevent existing installations from trusting future updates.

The current ad-hoc build uses an app-scoped library-validation exception because it has no Apple Team ID. Remove that exception when switching the app and embedded framework to Developer ID signing.

Sparkle signatures authenticate updates. They do not replace Apple Developer ID signing or notarization for the first download.

## Release steps

1. Increase `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`. The build number must increase with every release.
2. Run `scripts/build.sh`.
3. Download the matching Sparkle distribution to get its `generate_appcast` tool.
4. Create a release folder containing only the new app archive:

   ```sh
   mkdir -p build/update
   ditto -c -k --sequesterRsrc --keepParent build/Build/Products/Release/BendMac.app build/update/BendMac-macOS.zip
   ```

5. Copy the existing `docs/appcast.xml` into that folder. Generate the feed with your release tag in the download URL:

   ```sh
   /path/to/Sparkle/bin/generate_appcast --account BendMac --maximum-deltas 0 --download-url-prefix https://github.com/IuCC123/BendMac/releases/download/v0.4.0/ build/update
   ```

6. Upload the exact signed ZIP to that GitHub release. Do not rebuild or modify it after signing.
7. Copy the generated `appcast.xml` back to `docs/appcast.xml` and publish it only after the release asset is available.

Never commit private keys. Contributors can compile the app with the public key; only the release maintainer needs access to the private key.

Versions before 0.4.0 don't contain an updater. Those users need to download an updater-enabled version manually once.

## Drag-to-install download

Run `./scripts/dmg.sh` after building to create `build/BendMac-macOS.dmg`. It generates the Retina background and Finder layout without opening Finder. Upload the DMG alongside the ZIP and keep the filename `BendMac-macOS.dmg` on every release. The website uses GitHub’s `/releases/latest/download/BendMac-macOS.dmg` redirect, so the buttons follow the latest stable release without a website update. Publish each release only after both assets are uploaded. Keep the signed ZIP for Sparkle updates.
