import AppKit
import MetalKit

// Use the real AppModel and ScreenCaptureKit stream, with a controlled lid and
// discarded frames so this regression never displays an overlay or saves content.
struct BendParameters {
    var progress: Float = 0
    var perspective: Float = 1
    var blur: Float = 0.9
    var shadow: Float = 0.35
    var style: Float = 0
}
final class FrameStore {
    func get() -> CVPixelBuffer? { nil }
    func put(_ buffer: CVPixelBuffer, displayTime: UInt64) {}
    func clear() {}
}
final class BendRenderer {
    var parameters: @MainActor () -> BendParameters = { BendParameters() }
    init(frames: FrameStore) throws {}
    func makeView() -> MTKView { MTKView(frame: .zero) }
}
final class LidSensor {
    enum PollingMode { case idle, watching, active }
    var onAngle: ((Double?) -> Void)?
    func start() {}
    func reconnect() {}
    func setMode(_ mode: PollingMode) {}
    func setSuspended(_ suspended: Bool) {}
}

@main enum IdleCaptureRegression {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { @MainActor in
            let suite = "local.jamie.BendMac.idle-capture-tests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            let model = AppModel(defaults: defaults)
            do {
                model.followLid = false
                model.manualAngle = 115
                model.enable()
                try await wait("Open desktop did not become ready") { model.enabled }
                guard model.overlay == nil && model.capture.frameCount == 0 && !hasStream(model.capture)
                else {
                    throw failure("Enabling at an open angle started capture")
                }
                for cycle in 1...3 {
                    let before = model.capture.frameCount
                    model.manualAngle = 65
                    try await wait("Bending did not start real capture: \(model.status)") {
                        !model.starting && model.capture.frameCount > before
                    }
                    guard model.overlay?.isVisible == false else {
                        throw failure("Hidden capture test unexpectedly displayed an overlay")
                    }
                    model.manualAngle = 115
                    try await wait("Opening did not release the overlay") {
                        model.overlay == nil && model.parameters().progress == 0
                    }
                    // Allow asynchronous stop to finish, then prove callbacks stay stopped.
                    try await Task.sleep(for: .milliseconds(500))
                    let stoppedCount = model.capture.frameCount
                    try await Task.sleep(for: .seconds(1))
                    guard
                        model.capture.frameCount == stoppedCount && !hasStream(model.capture)
                            && model.enabled && model.wantsEnabled
                    else { throw failure("Screen capture continued after opening") }
                    print("PASS: real stream starts on bend and stops when open, hidden cycle \(cycle)")
                }
                model.disable()
                defaults.removePersistentDomain(forName: suite)
                exit(0)
            } catch {
                model.disable()
                defaults.removePersistentDomain(forName: suite)
                print("FAIL: \(error.localizedDescription)")
                exit(1)
            }
        }
        app.run()
    }
    @MainActor static func hasStream(_ capture: DesktopCapture) -> Bool {
        Mirror(reflecting: capture).children.first { $0.label == "stream" }
            .map { Mirror(reflecting: $0.value).children.count > 0 } ?? false
    }
    static func failure(_ message: String) -> NSError {
        NSError(domain: "IdleCaptureRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    @MainActor static func wait(_ message: String, until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(20))
        while !condition() && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        if !condition() { throw failure(message) }
    }
}
