import AppKit

let dir = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
        let n = Double(size)
        let bg = NSBezierPath(
            roundedRect: NSRect(x: n * 0.08, y: n * 0.08, width: n * 0.84, height: n * 0.84),
            xRadius: n * 0.19, yRadius: n * 0.19)
        NSGradient(colors: [
            NSColor(red: 0.1, green: 0.32, blue: 0.7, alpha: 1),
            NSColor(red: 0.48, green: 0.73, blue: 1, alpha: 1),
        ])!.draw(in: bg, angle: 65)
        let p = NSBezierPath()
        p.move(to: NSPoint(x: n * 0.23, y: n * 0.28))
        p.line(to: NSPoint(x: n * 0.77, y: n * 0.28))
        p.line(to: NSPoint(x: n * 0.66, y: n * 0.72))
        p.line(to: NSPoint(x: n * 0.34, y: n * 0.72))
        p.close()
        NSGradient(colors: [.white, NSColor(calibratedWhite: 0.8, alpha: 0.55)])!.draw(in: p, angle: 90)
        p.lineWidth = n * 0.02
        NSColor.white.setStroke()
        p.stroke()
        let base = NSBezierPath(
            roundedRect: NSRect(x: n * 0.17, y: n * 0.2, width: n * 0.66, height: n * 0.04),
            xRadius: n * 0.02, yRadius: n * 0.02)
        NSColor.white.setFill()
        base.fill()
        return true
    }
    let bitmap = NSBitmapImageRep(cgImage: image.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
    let data = bitmap.representation(using: .png, properties: [:])!
    if size <= 512 { try data.write(to: URL(fileURLWithPath: "\(dir)/icon_\(size)x\(size).png")) }
    if size >= 32 { try data.write(to: URL(fileURLWithPath: "\(dir)/icon_\(size/2)x\(size/2)@2x.png")) }
}
