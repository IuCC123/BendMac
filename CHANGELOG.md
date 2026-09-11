# Changelog

## [0.4.8](https://github.com/IuCC123/BendMac/releases/tag/v0.4.8) - 2026-09-11

BendMac 0.4.8 improves startup and recovery, remembers manual controls, and reduces background work when the desktop is not bending.

### Fixed

- Temporary screen-capture failures during launch, login, or wake now retry after each connection attempt finishes.
- Enabling before the lid sensor is ready now resumes when a valid reading arrives, including after the initial retry window has ended.
- Manual mode and its angle are restored together when you relaunch BendMac.
- Pausing during startup waits for the old connection to finish before reconnecting. Rapid pause and enable actions keep your latest choice.
- Capture refuses to start without excluding BendMac's own windows, preventing recursive desktop capture during startup and reconnects.
- A failed frame-rate update from an old connection no longer leaves a reconnected, visible effect running at the idle capture rate.
- Denied Screen Recording permission stops automatic retries and shows instructions for granting access.

### Changed

- The animation timer stops once the effect has settled. Lid polling slows down while the desktop is clear or manual mode is active, and pauses during sleep.
- The lid sensor continues checking for a device that becomes available later.

### Developer checks

- Added regression coverage for asynchronous recovery, cancellation, saved settings, and idle timers, plus live enable, bend, open, and pause cycles.
- Capture-exclusion checks now require a frame captured after the test overlay is confirmed visible.
- Removed unused shader parameters. GPU preview exports now report allocation, encoding, and file-writing failures instead of announcing success.


Earlier releases are documented in [GitHub Releases](https://github.com/IuCC123/BendMac/releases).
