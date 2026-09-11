import AppKit
import Carbon
import MetalKit
import ScreenCaptureKit
import ServiceManagement
import SwiftUI

final class OverlayWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor final class AppModel: ObservableObject {
    @Published var enabled = false
    @Published var starting = false
    @Published var status = "Ready to preview. Enable to bend your desktop."
    @Published var sensorAngle: Double?
    @Published var followLid = true {
        didSet {
            save()
            inputChanged()
        }
    }
    @Published var manualAngle = 115.0 {
        didSet {
            save()
            inputChanged()
        }
    }
    @Published var previewAngle = 105.0
    @Published var previewPlaying = false
    @Published var previewFollowsLid = false
    @Published var style = 0 { didSet { save() } }
    @Published var perspective = 1.0 { didSet { save() } }
    @Published var blur = 0.9 { didSet { save() } }
    @Published var shadow = 0.35 { didSet { save() } }
    @Published var clearAngle = 105.0 {
        didSet {
            save()
            inputChanged()
        }
    }
    @Published var sound = false { didSet { save() } }
    @Published private(set) var openAtLogin = SMAppService.mainApp.status == .enabled
    let frames = FrameStore()
    let previewFrames = FrameStore()
    let sensor = LidSensor()
    lazy var capture = DesktopCapture(frames: frames)
    var overlay: OverlayWindow?
    var renderer: BendRenderer?
    private var metalView: MTKView?
    private var timer: Timer?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var generation = 0
    private var stopping = false
    @Published private(set) var wantsEnabled = false {
        didSet { defaults.set(wantsEnabled, forKey: "enabled") }
    }
    private var sleeping = false
    private var needsUserAction = false
    private var reconnectTask: Task<Void, Never>?
    private var progress = 0.0
    private var lastTime = CACurrentMediaTime()
    private var playStart = 0.0
    private var wasFolded = false

    private var restoringPreferences = true
    private let defaults: UserDefaults
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Upgrade untouched v1 settings to the softer motion profile.
        if defaults.integer(forKey: "motionProfileVersion") < 3 {
            for (key, old, new) in [("perspective", 0.65, 1.0), ("blur", 0.65, 0.9), ("shadow", 0.65, 0.35)] {
                if let value = defaults.object(forKey: key) as? Double, abs(value - old) < 0.0001 {
                    defaults.set(new, forKey: key)
                }
            }
            defaults.set(3, forKey: "motionProfileVersion")
        }
        defaults.register(defaults: [
            "style": 0, "perspective": 1.0, "blur": 0.9, "shadow": 0.35, "clearAngle": 105.0, "sound": false,
            "followLid": true, "manualAngle": 115.0,
        ])
        style = defaults.integer(forKey: "style")
        perspective = defaults.double(forKey: "perspective")
        blur = defaults.double(forKey: "blur")
        shadow = defaults.double(forKey: "shadow")
        clearAngle = defaults.double(forKey: "clearAngle")
        sound = defaults.bool(forKey: "sound")
        followLid = defaults.bool(forKey: "followLid")
        let savedAngle = defaults.double(forKey: "manualAngle")
        manualAngle = savedAngle.isFinite ? min(135, max(12, savedAngle)) : 115
        restoringPreferences = false
        sensor.onAngle = { [weak self] angle in
            guard let self, !self.sleeping else { return }
            guard self.sensorAngle != angle else { return }
            let becameAvailable = self.sensorAngle == nil && angle != nil
            self.sensorAngle = angle
            if self.enabled || self.starting || becameAvailable { self.inputChanged() }
        }
        sensor.start()
        capture.onError = { [weak self] error in
            guard let self else { return }
            if Self.requiresUserAction(error) {
                self.disable(message: "Screen capture stopped. Enable BendMac again when you are ready.")
            } else {
                self.interrupt(message: "Capture interrupted: \(error.localizedDescription)")
            }
        }
        capture.onFirstFrame = { [weak self] in
            if self?.enabled == true { self?.startTicking() }
        }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(
            (
                center,
                center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) {
                    [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.sleeping = true
                        self.sensor.setSuspended(true)
                        self.interrupt(message: "Paused until your Mac wakes.")
                    }
                }
            ))
        observers.append(
            (
                center,
                center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) {
                    [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.sleeping = false
                        self.sensorAngle = nil
                        self.sensor.setSuspended(false)
                        self.sensor.reconnect()
                        self.scheduleReconnect()
                    }
                }
            ))
        observers.append(
            (
                NotificationCenter.default,
                NotificationCenter.default.addObserver(
                    forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        if self?.wantsEnabled == true {
                            self?.interrupt(message: "Reconnecting to your display…")
                        }
                    }
                }
            ))
        // Restore the effect after a relaunch, login, or update once the sensor reports.
        wantsEnabled = defaults.bool(forKey: "enabled")
        scheduleReconnect()
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, context in
                guard let context else { return OSStatus(eventNotHandledErr) }
                let model = Unmanaged<AppModel>.fromOpaque(context).takeUnretainedValue()
                MainActor.assumeIsolated { model.disable(message: "Paused with Escape.") }
                return noErr
            }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    deinit {
        reconnectTask?.cancel()
        timer?.invalidate()
        for (center, observer) in observers { center.removeObserver(observer) }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
    private func save() {
        guard !restoringPreferences else { return }
        defaults.set(style, forKey: "style")
        defaults.set(perspective, forKey: "perspective")
        defaults.set(blur, forKey: "blur")
        defaults.set(shadow, forKey: "shadow")
        defaults.set(clearAngle, forKey: "clearAngle")
        defaults.set(sound, forKey: "sound")
        defaults.set(followLid, forKey: "followLid")
        defaults.set(manualAngle, forKey: "manualAngle")
    }
    func setOpenAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            status = "Could not change Open at login: \(error.localizedDescription)"
        }
        if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        refreshOpenAtLogin()
    }
    func refreshOpenAtLogin() {
        openAtLogin = SMAppService.mainApp.status == .enabled
    }
    func parameters(preview: Bool = false) -> BendParameters {
        var p = BendParameters()
        p.progress = Float(
            preview ? BendMath.progress(angle: displayedPreviewAngle, clearAngle: clearAngle) : progress)
        p.perspective = Float(perspective)
        p.blur = Float(blur)
        p.shadow = Float(shadow)
        p.style = Float(style)
        return p
    }
    var displayedPreviewAngle: Double {
        previewFollowsLid ? (sensorAngle ?? clearAngle) : previewAngle
    }
    func calibrateOpenAngle() {
        guard let sensorAngle else { return }
        clearAngle = min(135, max(80, sensorAngle))
    }
    func resetAppearance() {
        perspective = 1
        blur = 0.9
        shadow = 0.35
        style = 0
    }
    func enable() {
        needsUserAction = false
        wantsEnabled = true
        scheduleReconnect(immediate: true)
    }

    private func inputChanged() {
        guard !restoringPreferences else { return }
        if followLid && sensorAngle == nil && (enabled || starting) {
            interrupt(message: "Waiting for the lid sensor… Turn off Follow lid to use a manual angle.")
        } else if enabled {
            startTicking()
        } else if wantsEnabled {
            scheduleReconnect(immediate: true)
        }
    }

    private enum ConnectionResult { case connected, retry, needsAttention }

    private static func requiresUserAction(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == SCStreamErrorDomain
            && [
                SCStreamError.Code.userDeclined.rawValue,
                SCStreamError.Code.userStopped.rawValue,
                SCStreamError.Code.missingEntitlements.rawValue,
            ].contains(error.code)
    }

    /// One complete attempt, including asynchronous capture startup and cleanup.
    private func connect(generation request: Int) async -> ConnectionResult {
        guard !followLid || sensorAngle != nil else {
            status = "Waiting for the lid sensor… Turn off Follow lid to use a manual angle."
            sensor.reconnect()
            return .retry
        }
        guard
            let screen = NSScreen.screens.first(where: {
                CGDisplayIsBuiltin(
                    ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
                        ?? 0
                ) != 0
            }),
            let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
                .uint32Value
        else {
            status = "Connect the built-in display to use the desktop effect."
            return .retry
        }
        starting = true
        status = "Connecting to your desktop…"
        var captureAttempted = false
        do {
            let renderer = try BendRenderer(frames: frames)
            renderer.parameters = { [weak self] in self?.parameters() ?? BendParameters() }
            let window = OverlayWindow(
                contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered, defer: false)
            window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
            window.isOpaque = true
            window.backgroundColor = .black
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.hidesOnDeactivate = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            let view = renderer.makeView()
            view.isPaused = true
            window.contentView = view
            window.setFrame(screen.frame, display: true)
            self.renderer = renderer
            overlay = window
            metalView = view
            // Register the hidden overlay before querying shareable content, including at login.
            captureAttempted = true
            try await capture.start(displayID: displayID)
            guard generation == request, !Task.isCancelled else { return .needsAttention }
            enabled = true
            starting = false
            progress = 0
            startTicking()
            status =
                followLid
                ? "Live desktop connected. Close the lid gently to bend it."
                : "Live desktop connected. Use the manual angle to bend it."
            if ProcessInfo.processInfo.arguments.contains("--smoke") { beginSmokeTest() }
            return .connected
        } catch {
            guard generation == request, !Task.isCancelled else { return .needsAttention }
            await capture.stop()
            guard generation == request, !Task.isCancelled else { return .needsAttention }
            clearOverlay()
            starting = false
            if Self.requiresUserAction(error) {
                status =
                    "Allow BendMac in System Settings → Privacy & Security → Screen & System Audio Recording, then try again."
                return .needsAttention
            }
            status = "Could not connect: \(error.localizedDescription)"
            // Hardware/Metal initialization errors need attention; capture can recover after login or wake.
            return captureAttempted ? .retry : .needsAttention
        }
    }
    private func interrupt(message: String) {
        guard wantsEnabled else { return }
        disable(message: message, preserveIntent: true)
    }
    private func scheduleReconnect(immediate: Bool = false) {
        guard reconnectTask == nil, wantsEnabled, !enabled, !starting, !stopping, !sleeping, !needsUserAction
        else { return }
        generation += 1
        let request = generation
        reconnectTask = Task { [weak self] in
            defer {
                if self?.generation == request { self?.reconnectTask = nil }
            }
            // Await the actual result; a temporary capture failure consumes an attempt, not the whole loop.
            for attempt in 0..<15 {
                if attempt > 0 || !immediate {
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                }
                guard let self, self.generation == request, self.wantsEnabled,
                    !self.sleeping, !Task.isCancelled
                else { return }
                switch await self.connect(generation: request) {
                case .connected: return
                case .needsAttention:
                    if self.generation == request { self.needsUserAction = true }
                    return
                case .retry: break
                }
            }
            if let self, self.generation == request {
                self.status += " Try connecting again."
            }
        }
    }
    private func clearOverlay() {
        overlay?.orderOut(nil)
        metalView?.isPaused = true
        overlay = nil
        renderer = nil
        metalView = nil
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
    }
    func disable(message: String = "Paused. Your desktop is back to normal.", preserveIntent: Bool = false) {
        if !preserveIntent { wantsEnabled = false }
        let pendingConnection = reconnectTask
        pendingConnection?.cancel()
        reconnectTask = nil
        generation += 1
        enabled = false
        progress = 0
        wasFolded = false
        sensor.setMode(.idle)
        clearOverlay()
        if !previewPlaying { stopTicking() }
        status = message
        guard !stopping else { return }
        stopping = true
        Task {
            await capture.stop()
            // A canceled start may still be inside ScreenCaptureKit. Drain it before opening another stream.
            await pendingConnection?.value
            stopping = false
            starting = false
            scheduleReconnect()
        }
    }
    func playPreview() {
        previewFollowsLid = false
        playStart = CACurrentMediaTime()
        previewPlaying = true
        startTicking()
    }
    private func stopTicking() {
        timer?.invalidate()
        timer = nil
    }
    /// Sensor/input changes restart smoothing; a settled effect needs no model timer.
    private func startTicking() {
        guard timer == nil else { return }
        lastTime = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    private func tick() {
        guard enabled || previewPlaying else {
            stopTicking()
            return
        }
        let now = CACurrentMediaTime()
        let dt = now - lastTime
        lastTime = now
        if previewPlaying {
            let t = (now - playStart) / 4.2
            if t >= 1 {
                previewPlaying = false
                previewAngle = clearAngle
            } else {
                previewAngle = clearAngle - (clearAngle - 18) * pow(sin(t * .pi), 2)
            }
        }
        guard enabled else {
            if !previewPlaying { stopTicking() }
            return
        }
        let angle = followLid ? (sensorAngle ?? clearAngle) : manualAngle
        let target = BendMath.progress(angle: angle, clearAngle: clearAngle)
        progress =
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? target : BendMath.smooth(current: progress, target: target, dt: dt)
        sensor.setMode(!followLid ? .idle : (target > 0 || progress > 0 ? .active : .watching))
        let visible = progress > 0.0005 && frames.get() != nil
        if visible && overlay?.isVisible == false {
            metalView?.isPaused = false
            overlay?.orderFrontRegardless()
            Task { await capture.setBending(true) }
            RegisterEventHotKey(
                UInt32(kVK_Escape), 0, EventHotKeyID(signature: 0x4245_4E44, id: 1),
                GetApplicationEventTarget(), 0, &hotKey)
        } else if !visible && overlay?.isVisible == true {
            overlay?.orderOut(nil)
            metalView?.isPaused = true
            Task { await capture.setBending(false) }
            if let hotKey {
                UnregisterEventHotKey(hotKey)
                self.hotKey = nil
            }
        }
        if !previewPlaying && progress == target { stopTicking() }
        if progress > 0.15 { wasFolded = true }
        if progress == 0 && wasFolded {
            wasFolded = false
            if sound { NSSound(named: "Tink")?.play() }
        }
    }
    private func beginSmokeTest() {
        let savedFollowLid = followLid
        let savedManualAngle = manualAngle
        followLid = false
        manualAngle = 42
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self else { return }
            let report =
                "frames=\(self.capture.frameCount) overlay=\(self.overlay?.isVisible == true) progress=\(self.progress) sensor=\(self.sensorAngle ?? -1)\n"
            try? report.write(toFile: "/tmp/bendmac-smoke.txt", atomically: true, encoding: .utf8)
            self.disable(message: "Live desktop test complete. Enable to follow your lid.")
            self.manualAngle = savedManualAngle
            self.followLid = savedFollowLid
        }
    }
}
