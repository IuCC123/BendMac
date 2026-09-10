import AppKit
import SwiftUI
import MetalKit
import Carbon

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
    let frames = FrameStore()
    let previewFrames = FrameStore()
    let sensor = LidSensor()
    lazy var capture = DesktopCapture(frames:frames)
    var overlay: OverlayWindow?
    var renderer: BendRenderer?
    private var metalView: MTKView?
    private var timer: Timer?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var generation = 0
    private var stopping = false
    private var progress = 0.0
    private var protectedTop: Float = 0
    private var lastTime = CACurrentMediaTime()
    private var playStart = 0.0
    private var wasFolded = false
    var showSettings: (() -> Void)?

    init() {
        let d = UserDefaults.standard
        // Upgrade untouched v1 settings to the softer motion profile.
        if d.integer(forKey:"motionProfileVersion") < 3 {
            for (key,old,new) in [("perspective",0.65,1.0),("blur",0.65,0.9),("shadow",0.65,0.35)] {
                if let value=d.object(forKey:key) as? Double, abs(value-old)<0.0001 { d.set(new,forKey:key) }
            }
            d.set(3,forKey:"motionProfileVersion")
        }
        d.register(defaults:["style":0,"perspective":1.0,"blur":0.9,"shadow":0.35,"clearAngle":105.0,"sound":false])
        style=d.integer(forKey:"style"); perspective=d.double(forKey:"perspective"); blur=d.double(forKey:"blur"); shadow=d.double(forKey:"shadow"); clearAngle=d.double(forKey:"clearAngle"); sound=d.bool(forKey:"sound")
        sensor.onAngle = { [weak self] angle in
            guard let self else { return }
            if self.sensorAngle != angle { self.sensorAngle = angle }
            if angle == nil && self.enabled && self.followLid { self.disable(message:"Lid sensor disconnected. Preview is still available.") }
        }
        sensor.start()
        capture.onError = { [weak self] message in self?.disable(message:"Capture stopped: \(message)") }
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName:NSWorkspace.willSleepNotification,object:nil,queue:.main) { [weak self] _ in
            MainActor.assumeIsolated { self?.disable(message:"Paused for sleep. Enable again when ready.") }
        }
        NotificationCenter.default.addObserver(forName:NSApplication.didChangeScreenParametersNotification,object:nil,queue:.main) { [weak self] _ in
            MainActor.assumeIsolated { if self?.enabled == true { self?.disable(message:"Display configuration changed. Enable again to reconnect.") } }
        }
        timer = Timer(timeInterval:1/60.0,repeats:true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
        RunLoop.main.add(timer!,forMode:.common)
        var spec = EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _,_,context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let model = Unmanaged<AppModel>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { model.disable(message:"Paused with Escape.") }
            return noErr
        },1,&spec,Unmanaged.passUnretained(self).toOpaque(),&handler)
    }
    private func save() {
        let d = UserDefaults.standard
        d.set(style,forKey:"style"); d.set(perspective,forKey:"perspective"); d.set(blur,forKey:"blur"); d.set(shadow,forKey:"shadow"); d.set(clearAngle,forKey:"clearAngle"); d.set(sound,forKey:"sound")
    }
    func parameters(preview: Bool = false) -> BendParameters {
        var p = BendParameters()
        p.progress = Float(preview ? BendMath.progress(angle:previewAngle,clearAngle:clearAngle) : progress)
        p.perspective=Float(perspective); p.blur=Float(blur); p.shadow=Float(shadow); p.style=Float(style)
        p.protectedTop = preview ? 0 : protectedTop
        return p
    }
    func enable() {
        guard !enabled, !starting, !stopping else { return }
        guard !followLid || sensorAngle != nil else { status="No lid sensor found. Turn off Follow lid to use the manual angle."; return }
        guard let screen = NSScreen.screens.first(where:{ CGDisplayIsBuiltin(($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0) != 0 }),
              let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { status="Connect the built-in display to use the desktop effect."; return }
        protectedTop=Float((screen.frame.maxY-screen.visibleFrame.maxY)/screen.frame.height)
        starting=true; status="Connecting to your desktop…"; generation += 1
        let currentGeneration = generation
        Task {
            do {
                try await capture.start(displayID:displayID)
                guard generation == currentGeneration else { await capture.stop(); return }
                let renderer = try BendRenderer(frames:frames)
                renderer.parameters = { [weak self] in self?.parameters() ?? BendParameters() }
                let window = OverlayWindow(contentRect:screen.frame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
                window.level = NSWindow.Level(rawValue:NSWindow.Level.statusBar.rawValue-1)
                window.isOpaque=true; window.backgroundColor = .black; window.hasShadow=false
                window.ignoresMouseEvents=true; window.hidesOnDeactivate=false
                window.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.stationary,.ignoresCycle]
                let view = renderer.makeView(); view.isPaused=true
                window.contentView=view; window.setFrame(screen.frame,display:true)
                self.renderer=renderer; overlay=window; metalView=view
                enabled=true; starting=false; progress=0; sensor.setActive(true)
                status="Live desktop connected. Close the lid gently to bend it."
                if ProcessInfo.processInfo.arguments.contains("--smoke") { beginSmokeTest() }
            } catch {
                await capture.stop()
                starting=false
                status="Screen capture could not start. Allow BendMac in System Settings → Privacy & Security → Screen & System Audio Recording, then try again. \(error.localizedDescription)"
            }
        }
    }
    func disable(message: String = "Paused. Your desktop is back to normal.") {
        generation += 1; enabled=false; progress=0; sensor.setActive(false)
        overlay?.orderOut(nil); metalView?.isPaused=true; overlay=nil; renderer=nil; metalView=nil
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey=nil }
        status=message
        stopping=true
        Task { await capture.stop(); stopping=false; starting=false }
    }
    func playPreview() { playStart=CACurrentMediaTime(); previewPlaying=true }
    private func tick() {
        let now=CACurrentMediaTime(); let dt=now-lastTime; lastTime=now
        if previewPlaying {
            let t=(now-playStart)/4.2
            if t >= 1 { previewPlaying=false; previewAngle=clearAngle }
            else { previewAngle=clearAngle-(clearAngle-18)*pow(sin(t * .pi),2) }
        }
        guard enabled else { return }
        let angle=followLid ? (sensorAngle ?? clearAngle) : manualAngle
        let target=BendMath.progress(angle:angle,clearAngle:clearAngle)
        progress = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? target : BendMath.smooth(current:progress,target:target,dt:dt)
        let visible = progress > 0.0005 && frames.get() != nil
        if visible && overlay?.isVisible == false {
            metalView?.isPaused=false; overlay?.orderFrontRegardless()
            Task { await capture.setBending(true) }
            RegisterEventHotKey(UInt32(kVK_Escape),0,EventHotKeyID(signature:0x42454E44,id:1),GetApplicationEventTarget(),0,&hotKey)
        } else if !visible && overlay?.isVisible == true {
            overlay?.orderOut(nil); metalView?.isPaused=true
            Task { await capture.setBending(false) }
            if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey=nil }
        }
        if progress > 0.15 { wasFolded=true }
        if progress == 0 && wasFolded { wasFolded=false; if sound { NSSound(named:"Tink")?.play() } }
    }
    private func beginSmokeTest() {
        followLid=false; manualAngle=42
        DispatchQueue.main.asyncAfter(deadline:.now()+3) { [weak self] in
            guard let self else { return }
            let report="frames=\(self.capture.frameCount) overlay=\(self.overlay?.isVisible == true) progress=\(self.progress) sensor=\(self.sensorAngle ?? -1)\n"
            try? report.write(toFile:"/tmp/bendmac-smoke.txt",atomically:true,encoding:.utf8)
            self.disable(message:"Live desktop test complete. Enable to follow your lid."); self.followLid=true
        }
    }
}
