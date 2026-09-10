import Foundation

// Render the website clip with the app's shader, without capturing the desktop.
@main
struct RenderDemo {
    static func main() throws {
        let folder = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let renderer = try BendRenderer(frames: FrameStore())
        for frame in 0...126 {
            try autoreleasepool {
                var parameters = BendParameters()
                let angle = 105 - 87 * pow(sin(Double(frame) / 126 * .pi), 2)
                parameters.progress = Float(BendMath.progress(angle: angle, clearAngle: 105))
                try renderer.exportPreview(parameters, to: folder.appendingPathComponent(
                    String(format: "frame-%03d.png", frame)))
            }
        }
    }
}
