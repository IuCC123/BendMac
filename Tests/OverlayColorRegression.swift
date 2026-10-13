import AppKit
import ScreenCaptureKit

/// Run with Screen Recording permission on a MacBook with the built-in display active.
/// A second app bundle briefly fills the display with a color chart, because BendMac excludes
/// its own app from capture. Screenshots stay in memory and are never saved.
@main enum OverlayColorRegression {
    static let chart = [
        NSColor(displayP3Red: 1, green: 0, blue: 0, alpha: 1),
        NSColor(displayP3Red: 0, green: 1, blue: 0, alpha: 1),
        NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1), NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1),
        NSColor(srgbRed: 0.9, green: 0.6, blue: 0.2, alpha: 1),
        NSColor(srgbRed: 0.2, green: 0.4, blue: 0.7, alpha: 1),
        NSColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1),
        NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
    ]

    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        guard let screen = NSScreen.screens.first(where: { CGDisplayIsBuiltin(displayID(of: $0)) != 0 })
        else {
            print("FAIL: the built-in display is not active")
            exit(1)
        }
        if CommandLine.arguments.contains("--chart") {
            showChart(on: screen)
        } else {
            Task { @MainActor in await run(on: screen) }
        }
        app.run()
    }

    @MainActor static func run(on screen: NSScreen) async {
        let chartProcess = Process()
        chartProcess.executableURL = URL(fileURLWithPath: CommandLine.arguments[1])
        chartProcess.arguments = ["--chart"]
        let suite = "local.jamie.BendMac.color-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let model = AppModel(defaults: defaults)
        func finish(_ code: Int32) -> Never {
            model.disable()
            chartProcess.terminate()
            defaults.removePersistentDomain(forName: suite)
            exit(code)
        }
        do {
            try chartProcess.run()
            try await Task.sleep(for: .seconds(1))
            model.followLid = false
            model.manualAngle = 115
            model.enable()
            try await wait("Effect did not become ready: \(model.status)") {
                model.enabled && model.overlay == nil
            }
            let desktop = try await screenshot(screen)
            let chartRed = desktop.rgb(x: desktop.width / 16, y: desktop.height / 2)
            guard chartRed[0] > 240 && chartRed[1] < 16 && chartRed[2] < 16 else {
                print("FAIL: the color chart is not on screen")
                finish(1)
            }
            // The smallest visible fold: geometry and blur are sub-pixel, so pixels must match.
            model.manualAngle = model.clearAngle - 1.5
            try await wait("The fold did not appear") { model.overlay?.isVisible == true }
            try await Task.sleep(for: .milliseconds(500))
            let folded = try await screenshot(screen)
            var failures = 0
            for band in chart.indices {
                for row in [0.35, 0.5, 0.65] {
                    let x = desktop.width * (2 * band + 1) / (2 * chart.count)
                    let y = Int(Double(desktop.height) * row)
                    let expected = desktop.rgb(x: x, y: y)
                    let actual = folded.rgb(x: x, y: y)
                    if zip(expected, actual).contains(where: { abs($0 - $1) > 3 }) {
                        print("FAIL: chart band \(band) shows \(actual) in the fold, desktop is \(expected)")
                        failures += 1
                    }
                }
            }
            if failures > 0 { finish(1) }
            print("PASS: a starting fold keeps the desktop's sRGB and Display P3 colors")
            finish(0)
        } catch {
            print("FAIL: \(error.localizedDescription); status=\(model.status)")
            finish(1)
        }
    }

    @MainActor static func showChart(on screen: NSScreen) {
        let window = NSWindow(
            contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.level = .floating
        window.ignoresMouseEvents = true
        window.contentView = ChartView()
        window.setFrame(screen.frame, display: true)
        window.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { exit(0) }
    }

    final class ChartView: NSView {
        override func draw(_ dirtyRect: NSRect) {
            let width = bounds.width / CGFloat(chart.count)
            for (index, color) in chart.enumerated() {
                color.setFill()
                NSRect(x: CGFloat(index) * width, y: 0, width: width, height: bounds.height).fill()
            }
        }
    }

    struct Pixels {
        let width: Int
        let height: Int
        let bytes: [UInt8]
        func rgb(x: Int, y: Int) -> [Int] {
            let offset = (y * width + x) * 4
            return (0..<3).map { Int(bytes[offset + $0]) }
        }
    }

    static func screenshot(_ screen: NSScreen) async throws -> Pixels {
        let id = displayID(of: screen)
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == id }) else {
            throw NSError(domain: "The built-in display is unavailable.", code: 1)
        }
        let config = SCStreamConfiguration()
        let mode = CGDisplayCopyDisplayMode(id)
        config.width = mode?.pixelWidth ?? display.width
        config.height = mode?.pixelHeight ?? display.height
        config.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(display: display, excludingWindows: []), configuration: config)
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(
            data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.displayP3)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Pixels(width: image.width, height: image.height, bytes: bytes)
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    @MainActor static func wait(_ message: String, until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(20))
        while !condition() && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        if !condition() {
            throw NSError(
                domain: "OverlayColorRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
}
