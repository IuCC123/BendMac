import AppKit
import ScreenCaptureKit

/// Run with Screen Recording permission on a Mac with an active display.
/// Uses a small colored panel; no screenshots or desktop content are saved.
@main enum CaptureRegression {
    @MainActor static func main() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let frames = FrameStore()
        let capture = DesktopCapture(frames: frames)
        guard let screen = NSScreen.screens.first,
            let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
                .uint32Value
        else { fatalError("An active display is required") }

        let initial = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        if !initial.applications.contains(where: { $0.processID == ProcessInfo.processInfo.processIdentifier }
        ) {
            do {
                try await capture.start(displayID: displayID)
                fatalError("Capture must reject a missing self-exclusion")
            } catch CaptureError.applicationUnavailable {
                print("PASS: missing self-exclusion fails safely")
            }
        }

        let panel = NSPanel(
            contentRect: NSRect(
                x: screen.frame.midX - 80, y: screen.frame.midY - 80, width: 160, height: 160),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.backgroundColor = .magenta
        panel.isOpaque = true
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.ignoresMouseEvents = true
        defer { panel.orderOut(nil) }

        // The regression is the login path: the first window exists but is hidden.
        for cycle in 1...3 {
            try await capture.start(displayID: displayID)
            try await Task.sleep(for: .milliseconds(500))
            panel.orderFrontRegardless()
            panel.displayIfNeeded()
            await capture.setBending(true)
            try await Task.sleep(for: .seconds(1))
            let visibleContent = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true)
            guard
                visibleContent.windows.contains(where: {
                    $0.windowID == CGWindowID(panel.windowNumber) && $0.isOnScreen
                })
            else { fatalError("The test overlay must actually be on screen") }
            let display = visibleContent.displays.first { $0.displayID == displayID }!
            let unfiltered = SCContentFilter(display: display, excludingWindows: [])
            let screenshotConfig = SCStreamConfiguration()
            screenshotConfig.width = display.width
            screenshotConfig.height = display.height
            let screenshot = try await SCScreenshotManager.captureImage(
                contentFilter: unfiltered, configuration: screenshotConfig)
            let bitmap = NSBitmapImageRep(cgImage: screenshot)
            let center = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)!.usingColorSpace(
                .deviceRGB)!
            guard center.redComponent > 0.8 && center.greenComponent < 0.55 && center.blueComponent > 0.8
            else {
                fatalError("Unfiltered control must contain the magenta overlay")
            }
            // Establish freshness only after the unfiltered control proves visibility.
            // Compare capture timestamps, so queued pre-presentation frames cannot pass.
            let visibleAt = mach_absolute_time()
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            var freshFrame = frames.get(after: visibleAt)
            while freshFrame == nil && ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
                freshFrame = frames.get(after: visibleAt)
            }
            guard let frame = freshFrame else {
                fatalError("No frame captured after verifying the visible overlay within five seconds")
            }
            CVPixelBufferLockBaseAddress(frame, .readOnly)
            let base = CVPixelBufferGetBaseAddress(frame)!.assumingMemoryBound(to: UInt8.self)
            let width = CVPixelBufferGetWidth(frame)
            let height = CVPixelBufferGetHeight(frame)
            let stride = CVPixelBufferGetBytesPerRow(frame)
            var magenta = 0
            for y in (height / 2 - 20)..<(height / 2 + 20) {
                for x in (width / 2 - 20)..<(width / 2 + 20) {
                    let pixel = base.advanced(by: y * stride + x * 4)
                    if pixel[0] > 200 && pixel[1] < 140 && pixel[2] > 200 { magenta += 1 }
                }
            }
            CVPixelBufferUnlockBaseAddress(frame, .readOnly)
            guard magenta < 100 else { fatalError("Overlay leaked into capture: \(magenta) magenta pixels") }
            panel.orderOut(nil)
            await capture.stop()
            guard frames.get() == nil else { fatalError("Stop must clear captured frames") }
            print("PASS: hidden-window start/reconnect \(cycle), visible overlay excluded, frames cleared")
        }
    }
}
