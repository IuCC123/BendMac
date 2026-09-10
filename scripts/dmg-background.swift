import AppKit

// Finder uses the 1x image size for its window and the @2x image on Retina displays.
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let size = NSSize(width: 660, height: 420)
for scale in [1, 2] {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 660 * scale, pixelsHigh: 420 * scale,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGradient(colors: [NSColor(calibratedWhite: 0.94, alpha: 1), .white])!
        .draw(in: NSRect(origin: .zero, size: size), angle: 90)

    func text(_ value: String, top: CGFloat, height: CGFloat, font: NSFont, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        (value as NSString).draw(
            in: NSRect(x: 24, y: size.height - top - height, width: size.width - 48, height: height),
            withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
    }

    text(
        "BendMac", top: 44, height: 44, font: .systemFont(ofSize: 32, weight: .semibold),
        color: .init(calibratedWhite: 0.12, alpha: 1))
    text(
        "A little flexibility for your desktop.", top: 93, height: 24, font: .systemFont(ofSize: 14),
        color: .init(calibratedWhite: 0.46, alpha: 1))

    // These wells sit behind Finder's actual draggable app and folder icons.
    for x: CGFloat in [120, 420] {
        let well = NSBezierPath(
            roundedRect: NSRect(x: x, y: 146, width: 120, height: 120), xRadius: 26, yRadius: 26)
        NSColor.white.withAlphaComponent(0.8).setFill()
        well.fill()
        NSColor.black.withAlphaComponent(0.045).setStroke()
        well.lineWidth = 1
        well.stroke()
    }
    let arrow = NSImage(systemSymbolName: "arrow.right", accessibilityDescription: nil)!
        .withSymbolConfiguration(.init(pointSize: 27, weight: .light))!
    arrow.draw(
        in: NSRect(x: 315, y: 193, width: 30, height: 26), from: .zero, operation: .sourceOver, fraction: 0.35
    )
    text(
        "Drag BendMac to Applications", top: 327, height: 26, font: .systemFont(ofSize: 15, weight: .medium),
        color: .init(calibratedWhite: 0.2, alpha: 1))
    text(
        "Free and open source · macOS 14+ · Apple silicon", top: 369, height: 20,
        font: .systemFont(ofSize: 11), color: .init(calibratedWhite: 0.5, alpha: 1))
    NSGraphicsContext.restoreGraphicsState()
    let name = scale == 1 ? "background.png" : "background@2x.png"
    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
}
