import AppKit

/// Exercises the actual model, capture, sensor, window, and Metal renderer.
/// Briefly bends the desktop. Uses isolated preferences and saves no screen content.
@main enum LiveEffectRegression {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { @MainActor in
            let suite = "local.jamie.BendMac.live-tests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            let model = AppModel(defaults: defaults)
            do {
                model.followLid = false
                model.manualAngle = 115
                for cycle in 1...3 {
                    model.enable()
                    try await wait("Live capture did not start: \(model.status)") {
                        model.enabled && model.frames.get() != nil
                    }
                    model.manualAngle = 65
                    try await wait("Effect did not become visible") {
                        model.overlay?.isVisible == true && model.parameters().progress > 0.35
                    }
                    model.manualAngle = 115
                    try await wait("Opening did not hide the effect and stop its timer") {
                        model.overlay?.isVisible == false && model.parameters().progress == 0
                            && !timerRunning(model)
                    }
                    model.disable()
                    try await wait("Pause did not clear captured frames") {
                        !model.enabled && model.overlay == nil && model.frames.get() == nil
                    }
                    print(
                        "PASS: live enable/bend/open/pause cycle \(cycle), idle timer stopped, frames cleared"
                    )
                }
                model.disable()
                defaults.removePersistentDomain(forName: suite)
                exit(0)
            } catch {
                model.disable()
                defaults.removePersistentDomain(forName: suite)
                print("FAIL: \(error.localizedDescription); status=\(model.status)")
                exit(1)
            }
        }
        app.run()
    }
    @MainActor static func timerRunning(_ model: AppModel) -> Bool {
        Mirror(reflecting: model).children.first { $0.label == "timer" }
            .map { Mirror(reflecting: $0.value).children.count > 0 } ?? false
    }
    @MainActor static func wait(_ message: String, until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(20))
        while !condition() && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        if !condition() {
            throw NSError(
                domain: "LiveEffectRegression", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
}
