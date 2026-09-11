import AppKit
import Carbon
import MetalKit
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
    @Published var followLid = true
    @Published var manualAngle = 115.0
    @Published var previewAngle = 70.0
    @Published var previewPlaying = false
    @Published var style = 0 { didSet { save() } }
    @Published var perspective = 1.0 { didSet { save() } }
    @Published var blur = 0.9 { didSet { save() } }
    @Published var shadow = 0.35 { didSet { save() } }
    @Published var clearAngle = 105.0 { didSet { save() } }
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
    private(set) var wantsEnabled = false {
        didSet { UserDefaults.standard.set(wantsEnabled, forKey: "enabled") }
    }
    private var sleeping = false
    private var reconnectTask: Task<Void, Never>?
    private var progress = 0.0
    private var protectedTop: Float = 0
    private var lastTime = CACurrentMediaTime()
    private var playStart = 0.0
    private var wasFolded = false

    init() {
        let defaults = UserDefaults.standard
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
        ])
        style = defaults.integer(forKey: "style")
        perspective = defaults.double(forKey: "perspective")
        blur = defaults.double(forKey: "blur")
        shadow = defaults.double(forKey: "shadow")
        clearAngle = defaults.double(forKey: "clearAngle")
        sound = defaults.bool(forKey: "sound")
        sensor.onAngle = { [weak self] angle in
            guard let self else { return }
            if self.sensorAngle != angle { self.sensorAngle = angle }
            if angle == nil && self.enabled && self.followLid {
                self.interrupt(message: "Waiting for the lid sensor…")
            }
        }
        sensor.start()
        capture.onError = { [weak self] message in self?.interrupt(message: "Capture interrupted: \(message)") }
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) {
            [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.sleeping = true
                self.interrupt(message: "Paused until your Mac wakes.")
            }
        }
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) {
            [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.sleeping = false
                self.sensorAngle = nil
                self.sensor.reconnect()
                self.scheduleReconnect()
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                if self?.wantsEnabled == true {
                    self?.interrupt(message: "Reconnecting to your display…")
                }
            }
        }
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
    private func save() {
        let defaults = UserDefaults.standard
        defaults.set(style, forKey: "style")
        defaults.set(perspective, forKey: "perspective")
        defaults.set(blur, forKey: "blur")
        defaults.set(shadow, forKey: "shadow")
        defaults.set(clearAngle, forKey: "clearAngle")
        defaults.set(sound, forKey: "sound")
    }
    func setOpenAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            status = "Could not change Open at login: \(error.localizedDescription)"
        }
        if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        openAtLogin = SMAppService.mainApp.status == .enabled
    }
    func parameters(preview: Bool = false) -> BendParameters {
        var p = BendParameters()
        p.progress = Float(
            preview ? BendMath.progress(angle: previewAngle, clearAngle: clearAngle) : progress)
        p.perspective = Float(perspective)
        p.blur = Float(blur)
        p.shadow = Float(shadow)
        p.style = Float(style)
        p.protectedTop = preview ? 0 : protectedTop
        return p
    }
    func enable() {
        guard !enabled, !starting, !stopping, !sleeping else { return }
        wantsEnabled = true
        guard !followLid || sensorAngle != nil else {
            status = "No lid sensor found. Turn off Follow lid to use the manual angle."
            return
        }
        guard
            let screen = NSScreen.screens.first(where: {
                CGDisplayIsBuiltin(
                    ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
                        ?? 0) != 0
            }),
            let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
                .uint32Value
        else {
            status = "Connect the built-in display to use the desktop effect."
            return
        }
        protectedTop = Float((screen.frame.maxY - screen.visibleFrame.maxY) / screen.frame.height)
        starting = true
        status = "Connecting to your desktop…"
        generation += 1
        let currentGeneration = generation
        Task {
            do {
                try await capture.start(displayID: displayID)
                guard generation == currentGeneration else { return }
                let renderer = try BendRenderer(frames: frames)
                renderer.parameters = { [weak self] in self?.parameters() ?? BendParameters() }
                let window = OverlayWindow(
                    contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                    backing: .buffered, defer: false)
                window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1)
                window.isOpaque = true
                window.backgroundColor = .black
                window.hasShadow = false
                window.ignoresMouseEvents = true
                window.hidesOnDeactivate = false
                window.collectionBehavior = [
                    .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle,
                ]
                let view = renderer.makeView()
                view.isPaused = true
                window.contentView = view
                window.setFrame(screen.frame, display: true)
                self.renderer = renderer
                overlay = window
                metalView = view
                enabled = true
                starting = false
                startTicking()
                progress = 0
                sensor.setActive(true)
                status = "Live desktop connected. Close the lid gently to bend it."
                if ProcessInfo.processInfo.arguments.contains("--smoke") { beginSmokeTest() }
            } catch {
                guard generation == currentGeneration else { return }
                await capture.stop()
                guard generation == currentGeneration else { return }
                starting = false
                status =
                    "Screen capture could not start. Allow BendMac in System Settings → Privacy & Security → Screen & System Audio Recording, then try again. \(error.localizedDescription)"
            }
        }
    }
    private func interrupt(message: String) {
        guard wantsEnabled else { return }
        disable(message: message, preserveIntent: true)
        scheduleReconnect()
    }
    private func scheduleReconnect() {
        reconnectTask?.cancel()
        guard wantsEnabled, !sleeping else { return }
        reconnectTask = Task { [weak self] in
            // Wake notifications can arrive before the display and HID device are ready.
            for _ in 0..<15 {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self, self.wantsEnabled, !self.sleeping else { return }
                guard !self.stopping, !self.starting else { continue }
                if self.followLid && self.sensorAngle == nil {
                    self.sensor.reconnect()
                    continue
                }
                guard NSScreen.screens.contains(where: {
                    CGDisplayIsBuiltin(($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0) != 0
                }) else { continue }
                self.enable()
                return
            }
            self?.status = "Could not reconnect. Try enabling BendMac again."
        }
    }
    func disable(message: String = "Paused. Your desktop is back to normal.", preserveIntent: Bool = false) {
        if !preserveIntent { wantsEnabled = false }
        reconnectTask?.cancel()
        reconnectTask = nil
        generation += 1
        enabled = false
        progress = 0
        sensor.setActive(false)
        overlay?.orderOut(nil)
        metalView?.isPaused = true
        overlay = nil
        renderer = nil
        metalView = nil
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        status = message
        guard !stopping else { return }
        stopping = true
        Task {
            await capture.stop()
            stopping = false
            starting = false
        }
    }
    func playPreview() {
        playStart = CACurrentMediaTime()
        previewPlaying = true
        startTicking()
    }
    /// Runs only while the effect or preview animates, so the idle menu bar app doesn't wake 60 times a second.
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
            timer?.invalidate()
            timer = nil
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
        guard enabled else { return }
        let angle = followLid ? (sensorAngle ?? clearAngle) : manualAngle
        let target = BendMath.progress(angle: angle, clearAngle: clearAngle)
        progress =
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? target : BendMath.smooth(current: progress, target: target, dt: dt)
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
        if progress > 0.15 { wasFolded = true }
        if progress == 0 && wasFolded {
            wasFolded = false
            if sound { NSSound(named: "Tink")?.play() }
        }
    }
    private func beginSmokeTest() {
        followLid = false
        manualAngle = 42
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self else { return }
            let report =
                "frames=\(self.capture.frameCount) overlay=\(self.overlay?.isVisible == true) progress=\(self.progress) sensor=\(self.sensorAngle ?? -1)\n"
            try? report.write(toFile: "/tmp/bendmac-smoke.txt", atomically: true, encoding: .utf8)
            self.disable(message: "Live desktop test complete. Enable to follow your lid.")
            self.followLid = true
        }
    }
}
