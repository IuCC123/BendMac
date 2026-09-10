import AppKit
import MetalKit
import MetalPerformanceShaders
import CoreVideo

struct BendParameters {
    var progress: Float = 0
    var perspective: Float = 1
    var blur: Float = 0.9
    var shadow: Float = 0.35
    var aspect: Float = 1.6
    var style: Float = 0
    var protectedTop: Float = 0
    var pad2: Float = 0
}

final class FrameStore {
    private let lock = NSLock()
    private var latest: CVPixelBuffer?
    func put(_ frame: CVPixelBuffer) { lock.lock(); latest = frame; lock.unlock() }
    func get() -> CVPixelBuffer? { lock.lock(); defer { lock.unlock() }; return latest }
    func clear() { lock.lock(); latest = nil; lock.unlock() }
}

final class BendRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private var cache: CVMetalTextureCache!
    private let fallback: MTLTexture
    private var blurTextures = [MTLTexture]()
    private var blurKernels = [MPSImageGaussianBlur]()
    private var blurStrength: Float = -1
    let frames: FrameStore
    var parameters: @MainActor () -> BendParameters = { BendParameters() }
    var onDraw: (() -> Void)?

    init(frames: FrameStore, preview: CGImage? = nil) throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary() else { throw NSError(domain: "Metal unavailable", code: 1) }
        self.device = device; self.queue = queue; self.frames = frames
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "bendVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "bendFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        let cg = preview ?? Self.previewImage()
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba8Unorm,width:cg.width,height:cg.height,mipmapped:false)
        guard let texture = device.makeTexture(descriptor:td) else { throw NSError(domain:"Preview texture allocation failed",code:2) }
        var pixels = [UInt8](repeating:0,count:cg.width*cg.height*4)
        pixels.withUnsafeMutableBytes { bytes in
            let context = CGContext(data:bytes.baseAddress,width:cg.width,height:cg.height,bitsPerComponent:8,bytesPerRow:cg.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(cg,in:CGRect(x:0,y:0,width:cg.width,height:cg.height))
            texture.replace(region:MTLRegionMake2D(0,0,cg.width,cg.height),mipmapLevel:0,withBytes:bytes.baseAddress!,bytesPerRow:cg.width*4)
        }
        fallback = texture
        super.init()
        CVMetalTextureCacheCreate(nil,nil,device,nil,&cache)
    }
    func makeView() -> MTKView {
        let view = MTKView(frame: .zero, device: device)
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColorMake(0,0,0,1)
        view.preferredFramesPerSecond = 60
        view.framebufferOnly = false
        view.delegate = self
        return view
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable, let pass = view.currentRenderPassDescriptor,
              let command = queue.makeCommandBuffer() else { return }
        var retained: CVMetalTexture?
        var texture = fallback
        if let frame = frames.get() {
            CVMetalTextureCacheCreateTextureFromImage(nil,cache,frame,nil,.bgra8Unorm,CVPixelBufferGetWidth(frame),CVPixelBufferGetHeight(frame),0,&retained)
            if let retained, let live = CVMetalTextureGetTexture(retained) { texture = live }
        }
        var p = MainActor.assumeIsolated { parameters() }
        p.aspect = Float(view.drawableSize.width / max(1,view.drawableSize.height))
        let blurred = encodeBlur(texture,command:command,strength:p.blur)
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(texture,index:0)
        for (i,t) in blurred.enumerated() { encoder.setFragmentTexture(t,index:i+1) }
        encoder.setFragmentBytes(&p,length:MemoryLayout<BendParameters>.stride,index:0)
        encoder.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:3)
        encoder.endEncoding()
        command.present(drawable)
        // Retain the CV-backed texture until GPU completion.
        let held = retained
        command.addCompletedHandler { _ in withExtendedLifetime(held) {} }
        command.commit()
        onDraw?()
    }
    private func encodeBlur(_ source: MTLTexture, command: MTLCommandBuffer, strength: Float) -> [MTLTexture] {
        if strength < 0.001 { return [source,source,source,source] }
        let w=max(1,source.width/4), h=max(1,source.height/4)
        if blurTextures.first?.width != w || blurTextures.first?.height != h {
            let descriptor=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba8Unorm,width:w,height:h,mipmapped:false)
            descriptor.usage=[.shaderRead,.shaderWrite]; descriptor.storageMode = .private
            blurTextures=(0..<5).compactMap { _ in device.makeTexture(descriptor:descriptor) }
            blurStrength = -1
        }
        guard blurTextures.count == 5 else { return [source,source,source,source] }
        if abs(blurStrength-strength) > 0.001 {
            blurKernels=[4.0,10.0,28.0,64.0].map {
                let kernel=MPSImageGaussianBlur(device:device,sigma:Float($0)*Float(w)/880*strength/0.9)
                kernel.edgeMode = .clamp
                return kernel
            }
            blurStrength=strength
        }
        MPSImageBilinearScale(device:device).encode(commandBuffer:command,sourceTexture:source,destinationTexture:blurTextures[0])
        for i in 0..<4 { blurKernels[i].encode(commandBuffer:command,sourceTexture:blurTextures[0],destinationTexture:blurTextures[i+1]) }
        return Array(blurTextures.dropFirst())
    }
    /// Offline QA uses the very same compiled GPU pipeline and preview texture.
    func exportPreview(_ p: BendParameters, to url: URL) throws {
        let w=960, h=600
        let td=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.bgra8Unorm,width:w,height:h,mipmapped:false)
        td.usage=[.renderTarget,.shaderRead]; td.storageMode = .shared
        guard let texture=device.makeTexture(descriptor:td), let command=queue.makeCommandBuffer() else { return }
        let pass=MTLRenderPassDescriptor(); pass.colorAttachments[0].texture=texture
        pass.colorAttachments[0].loadAction = .clear; pass.colorAttachments[0].storeAction = .store
        let blurred = encodeBlur(fallback,command:command,strength:p.blur)
        guard let encoder=command.makeRenderCommandEncoder(descriptor:pass) else { return }
        var params=p; params.aspect=Float(w)/Float(h)
        encoder.setRenderPipelineState(pipeline); encoder.setFragmentTexture(fallback,index:0)
        for (i,t) in blurred.enumerated() { encoder.setFragmentTexture(t,index:i+1) }
        encoder.setFragmentBytes(&params,length:MemoryLayout<BendParameters>.stride,index:0)
        encoder.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:3); encoder.endEncoding()
        command.commit(); command.waitUntilCompleted()
        if let error=command.error { throw error }
        var pixels=[UInt8](repeating:0,count:w*h*4)
        texture.getBytes(&pixels,bytesPerRow:w*4,from:MTLRegionMake2D(0,0,w,h),mipmapLevel:0)
        let data=Data(pixels)
        let cg=CGImage(width:w,height:h,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedFirst.rawValue).union(.byteOrder32Little),provider:CGDataProvider(data:data as CFData)!,decode:nil,shouldInterpolate:true,intent:.defaultIntent)!
        try NSBitmapImageRep(cgImage:cg).representation(using:.png,properties:[:])!.write(to:url)
    }
    static func previewImage() -> CGImage {
        let size = NSSize(width:1280,height:800)
        let image = NSImage(size:size, flipped:false) { rect in
            NSGradient(colors:[NSColor(red:0.16,green:0.23,blue:0.34,alpha:1),NSColor(red:0.57,green:0.65,blue:0.75,alpha:1)])!.draw(in:rect,angle:90)
            for layer in stride(from:4,through:0,by:-1) {
                let path = NSBezierPath(); path.move(to:.zero)
                for i in 0...100 {
                    let x = Double(i)/100*1280
                    let y = 130 + Double(layer)*65 + sin(x/210+Double(layer)*1.1)*45 + sin(x/95+Double(layer))*15
                    path.line(to:NSPoint(x:x,y:y))
                }
                path.line(to:NSPoint(x:1280,y:0)); path.close()
                NSColor(calibratedRed:0.15+Double(layer)*0.09,green:0.2+Double(layer)*0.09,blue:0.28+Double(layer)*0.09,alpha:1).setFill(); path.fill()
            }
            let snow = NSBezierPath(); snow.move(to:.zero); snow.line(to:NSPoint(x:0,y:185)); snow.curve(to:NSPoint(x:1280,y:315),controlPoint1:NSPoint(x:500,y:320),controlPoint2:NSPoint(x:600,y:30)); snow.line(to:NSPoint(x:1280,y:0)); snow.close()
            NSColor(calibratedRed:0.77,green:0.83,blue:0.89,alpha:1).setFill(); snow.fill()
            NSColor(calibratedWhite:0.93,alpha:1).setFill(); NSBezierPath(ovalIn:NSRect(x:950,y:570,width:70,height:70)).fill()
            let centered = NSMutableParagraphStyle(); centered.alignment = .center
            ("Thursday, September 10" as NSString).draw(in:NSRect(x:0,y:630,width:1280,height:30),withAttributes:[.font:NSFont.systemFont(ofSize:23,weight:.medium),.foregroundColor:NSColor.white,.paragraphStyle:centered])
            ("9:41" as NSString).draw(in:NSRect(x:0,y:488,width:1280,height:145),withAttributes:[.font:NSFont.systemFont(ofSize:126,weight:.light),.foregroundColor:NSColor.white,.paragraphStyle:centered])
            return true
        }
        return image.cgImage(forProposedRect:nil,context:nil,hints:nil)!
    }
}
