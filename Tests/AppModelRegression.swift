import AppKit
import MetalKit
import ScreenCaptureKit

// Compile the real AppModel against controlled capture, sensor, and renderer doubles.
// No screen capture, visible overlay, hardware access, or standard preferences are used.
struct BendParameters {
    var progress: Float = 0
    var perspective: Float = 1
    var blur: Float = 0.9
    var shadow: Float = 0.35
    var style: Float = 0
}
final class FrameStore { func get() -> CVPixelBuffer? { nil } }
final class BendRenderer {
    var parameters: @MainActor () -> BendParameters = { BendParameters() }
    init(frames: FrameStore) throws {}
    func makeView() -> MTKView { MTKView(frame: .zero) }
}
final class LidSensor {
    enum PollingMode { case idle, watching, active }
    var onAngle: ((Double?) -> Void)?
    var mode: PollingMode = .idle
    var suspended = false
    func start() {}
    func reconnect() {}
    func setMode(_ mode: PollingMode) { self.mode = mode }
    func setSuspended(_ suspended: Bool) { self.suspended = suspended }
}
@MainActor final class DesktopCapture {
    var onError: ((Error) -> Void)?
    var onFirstFrame: (() -> Void)?
    var failures: [Error] = []
    var attempts = 0
    var activeStarts = 0
    var maxActiveStarts = 0
    var holdStart = false
    var heldStart: CheckedContinuation<Void, Never>?
    var generation = 0
    var frameCount: Int { 0 }
    init(frames: FrameStore) {}
    func start(displayID: CGDirectDisplayID) async throws {
        let request = generation
        attempts += 1
        activeStarts += 1
        maxActiveStarts = max(maxActiveStarts, activeStarts)
        defer { activeStarts -= 1 }
        if holdStart {
            holdStart = false
            await withCheckedContinuation { heldStart = $0 }
        } else {
            try await Task.sleep(for: .milliseconds(40))
        }
        guard request == generation else { throw CancellationError() }
        if !failures.isEmpty { throw failures.removeFirst() }
    }
    func stop() async { generation += 1 }
    func setBending(_ active: Bool) async {}
}

@main enum AppModelRegression {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { @MainActor in
            await run()
            exit(0)
        }
        app.run()
    }
    @MainActor static func check(_ result: Bool, _ message: String) {
        if !result { fatalError(message) }
    }
    @MainActor static func wait(_ message: String, seconds: Double = 5, until condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() && Date() < deadline { try? await Task.sleep(for: .milliseconds(20)) }
        check(condition(), message)
    }
    @MainActor static func timerRunning(_ model: AppModel) -> Bool {
        // Observe the actual timer without adding a production testing API.
        Mirror(reflecting: model).children.first { $0.label == "timer" }
            .map { Mirror(reflecting: $0.value).children.count > 0 } ?? false
    }
    @MainActor static func run() async {
        let suite = "local.jamie.BendMac.lifecycle-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults)
        model.followLid = false
        model.manualAngle = 115
        let transient = NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.failedToStart.rawValue)
        model.capture.failures = [transient, transient]
        model.enable()
        await wait("Transient asynchronous failures must retry through success") { model.enabled }
        check(model.capture.attempts == 3, "Expected three complete connection attempts")
        await wait("Open manual mode must stop its model timer") { !timerRunning(model) }
        check(model.sensor.mode == .idle, "Manual mode must not poll sensor at 60 Hz")
        print("PASS: asynchronous startup retries, idle model timer, manual sensor polling")

        model.manualAngle = 42
        await wait("Manual input must restart and settle the animation") {
            model.parameters().progress > 0.7 && !timerRunning(model)
        }
        model.capture.onFirstFrame?()
        check(timerRunning(model), "First frame must wake an animation that settled before capture delivered")
        model.manualAngle = 115
        await wait("Opening must settle at zero and stop ticking") {
            model.parameters().progress == 0 && !timerRunning(model)
        }
        model.followLid = true
        await wait("Missing sensor must pause capture") { !model.enabled && !model.starting }
        model.sensor.onAngle?(120)
        await wait("A pending enable must resume when sensor appears") { model.enabled }
        await wait("Open physical lid must use watching rate") {
            model.sensor.mode == .watching && !timerRunning(model)
        }
        model.sensor.onAngle?(42)
        await wait("Lid motion must resume animation and fast sensor rate") {
            model.parameters().progress > 0.7 && model.sensor.mode == .active
        }
        model.sensor.onAngle?(120)
        await wait("Open lid must restore reduced polling and settle") {
            !timerRunning(model) && model.sensor.mode == .watching
        }
        print(
            "PASS: manual/lid input resumes animation, sensor arrival resumes pending enable, adaptive polling"
        )

        model.disable()
        await wait("Disable must complete") { !model.starting }
        try? await Task.sleep(for: .milliseconds(100))
        model.followLid = false
        model.capture.holdStart = true
        model.enable()
        await wait("Test must reach suspended asynchronous start") { model.capture.heldStart != nil }
        let attemptsBeforeCancel = model.capture.attempts
        model.disable()
        model.enable()
        try? await Task.sleep(for: .milliseconds(150))
        check(
            model.capture.attempts == attemptsBeforeCancel,
            "New start must wait for canceled startup to drain")
        model.capture.heldStart?.resume()
        model.capture.heldStart = nil
        await wait("Re-enable during teardown must eventually connect") { model.enabled }
        check(model.capture.maxActiveStarts == 1, "Capture starts must never overlap")
        print("PASS: canceled startup drains, rapid disable/enable preserves latest intent")

        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        check(
            !model.enabled && model.sensor.suspended && model.wantsEnabled,
            "Sleep must hide effect and preserve intent")
        model.capture.failures = [transient]
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        await wait("Wake must retry asynchronous failure") { model.enabled }
        check(!model.sensor.suspended, "Wake must resume sensor")
        let beforeInterruption = model.capture.attempts
        model.capture.onError?(transient)
        await wait("Interrupted live capture must reconnect") {
            model.enabled && model.capture.attempts > beforeInterruption
        }
        print("PASS: sleep/wake and live capture interruption recovery")

        model.disable()
        try? await Task.sleep(for: .milliseconds(100))
        model.capture.failures = [
            NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.userDeclined.rawValue)
        ]
        let beforeDenial = model.capture.attempts
        model.enable()
        await wait("Permission denial must finish startup with guidance") {
            model.status.contains("Allow BendMac")
        }
        model.followLid = true
        model.sensor.onAngle?(118)
        model.sensor.onAngle?(119)
        try? await Task.sleep(for: .milliseconds(1300))
        check(
            model.capture.attempts == beforeDenial + 1,
            "Permission denial must not repeatedly prompt on sensor/input changes")
        model.enable()
        await wait("Explicit retry after permission correction must work") { model.enabled }
        model.disable()
        try? await Task.sleep(for: .milliseconds(100))
        check(!model.wantsEnabled && !defaults.bool(forKey: "enabled"), "Pause must persist disabled intent")
        print("PASS: permission denial stops retries; explicit retry succeeds; pause persists")

        // Exhaust sensor readiness retries, then verify an event can still recover it.
        model.sensor.onAngle?(nil)
        model.enable()
        await wait("Sensor readiness retries must be bounded", seconds: 17) {
            model.status.contains("Try connecting again")
        }
        model.sensor.onAngle?(120)
        await wait("Late sensor arrival must recover after retry exhaustion") { model.enabled }
        model.followLid = false
        model.manualAngle = 53
        model.disable(preserveIntent: true)
        // Termination preserves preferences; prevent this test instance from reconnecting.
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        let restored = AppModel(defaults: defaults)
        check(
            !restored.followLid && restored.manualAngle == 53 && restored.wantsEnabled,
            "Relaunch must restore manual mode, angle, and intent together")
        restored.disable()
        model.disable()
        print("PASS: late sensor recovery and persisted manual-mode relaunch")
    }
}
