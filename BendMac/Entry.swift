import AppKit
import SwiftUI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var model: AppModel!
    var statusItem: NSStatusItem!
    var settings: NSWindow?
    let updates = UpdateController()
    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel()
        updates.start()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "macbook", accessibilityDescription: "BendMac")
        statusItem.button?.toolTip = "BendMac — desktop fold"
        let menu = NSMenu()
        menu.addItem(withTitle: "BendMac", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        let toggle = menu.addItem(
            withTitle: "Enable / pause effect", action: #selector(toggleEffect), keyEquivalent: "")
        toggle.target = self
        let settingsItem = menu.addItem(
            withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        let preview = menu.addItem(
            withTitle: "Play preview", action: #selector(playPreview), keyEquivalent: "")
        preview.target = self
        let updateItem = menu.addItem(
            withTitle: "Check for Updates…", action: #selector(UpdateController.checkForUpdates),
            keyEquivalent: "")
        updateItem.target = updates
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit BendMac", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        openSettings()
        if CommandLine.arguments.contains("--smoke") { model.enable() }
    }
    @objc func toggleEffect() { if model.enabled { model.disable() } else { model.enable() } }
    @objc func playPreview() {
        openSettings()
        model.playPreview()
    }
    @objc func openSettings() {
        if settings == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 800, height: 720),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false)
            window.title = "BendMac"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            window.titlebarSeparatorStyle = .none
            window.isMovableByWindowBackground = true
            window.contentMinSize = NSSize(width: 740, height: 670)
            window.contentView = NSHostingView(rootView: SettingsView(model: model, updates: updates))
            window.center()
            window.delegate = self
            settings = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settings?.makeKeyAndOrderFront(nil)
    }
    func applicationWillTerminate(_ notification: Notification) { model.disable() }
}
@main enum BendMacMain {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--sensor-check") {
            let sensor = LidSensor()
            print(sensor.read().map { "Lid angle: \(Int($0)) degrees" } ?? "Lid sensor unavailable")
            exit(0)
        }

        if let index = CommandLine.arguments.firstIndex(of: "--render-proof"),
            CommandLine.arguments.count > index + 1
        {
            let folder = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                var reference: CGImage?
                if let ref = CommandLine.arguments.firstIndex(of: "--reference-image"),
                    CommandLine.arguments.count > ref + 1
                {
                    reference = NSImage(contentsOfFile: CommandLine.arguments[ref + 1])?.cgImage(
                        forProposedRect: nil, context: nil, hints: nil)
                    guard reference != nil else {
                        throw NSError(domain: "Reference image could not be read", code: 1)
                    }
                }
                let renderer = try BendRenderer(frames: FrameStore(), preview: reference)
                for frame in 0...126 {
                    var p = BendParameters()
                    let angle = 105 - 87 * pow(sin(Double(frame) / 126 * .pi), 2)
                    p.progress = Float(BendMath.progress(angle: angle, clearAngle: 105))
                    try renderer.exportPreview(
                        p, to: folder.appendingPathComponent(String(format: "frame-%03d.png", frame)))
                }
                print("Rendered 127 GPU frames successfully")
            } catch {
                print("Render failed: \(error)")
                exit(1)
            }
            exit(0)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
