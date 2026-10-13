import CoreVideo
import Foundation
import Metal

/// Frees texture caches while the GPU releases their last frame, as the overlay does when a fold
/// ends. Draws nothing on screen.
@main enum TextureCacheRegression {
    static func main() {
        let device = MTLCreateSystemDefaultDevice()!
        let queue = device.makeCommandQueue()!
        let width = 2880
        let height = 1864
        var frame: CVPixelBuffer?
        CVPixelBufferCreate(
            nil, width, height, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferMetalCompatibilityKey: true, kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary,
            &frame)
        let target = device.makeTexture(
            descriptor: .texture2DDescriptor(
                pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false))!
        for _ in 0..<4000 {
            var cache: CVMetalTextureCache?
            CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
            var texture: CVMetalTexture?
            CVMetalTextureCacheCreateTextureFromImage(
                nil, cache!, frame!, nil, .bgra8Unorm, width, height, 0, &texture)
            let command = queue.makeCommandBuffer()!
            let blit = command.makeBlitCommandEncoder()!
            blit.copy(from: CVMetalTextureGetTexture(texture!)!, to: target)
            blit.endEncoding()
            command.hold(texture, frame: frame, from: cache!)
            texture = nil
            command.commit()
            command.waitUntilScheduled()
            // Land the cache's last release near the GPU's completion handler.
            usleep(UInt32.random(in: 0...1500))
            cache = nil
        }
        queue.makeCommandBuffer().map {
            $0.commit()
            $0.waitUntilCompleted()
        }
        Thread.sleep(forTimeInterval: 0.2)
        print("PASS: 4000 texture caches freed while the GPU released their frames")
    }
}
