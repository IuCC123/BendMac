import ScreenCaptureKit
import CoreMedia

final class DesktopCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    let frames: FrameStore
    @MainActor private var stream: SCStream?
    @MainActor private var config: SCStreamConfiguration?
    private let queue = DispatchQueue(label: "local.jamie.BendMac.capture", qos: .userInteractive)
    var onError: ((String) -> Void)?
    var onFrame: (() -> Void)?
    private let countLock = NSLock()
    private var count = 0
    var frameCount: Int { countLock.lock(); defer { countLock.unlock() }; return count }
    init(frames: FrameStore) { self.frames = frames }

    @MainActor func start(displayID: CGDirectDisplayID) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false,onScreenWindowsOnly:true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw NSError(domain:"The built-in display is unavailable.",code:1)
        }
        let ownApp = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        // Exclude our entire process to prevent recursive capture of the overlay and settings.
        let filter = SCContentFilter(display:display,excludingApplications:ownApp,exceptingWindows:[])
        let config = SCStreamConfiguration()
        config.width = CGDisplayPixelsWide(displayID)
        config.height = CGDisplayPixelsHigh(displayID)
        config.minimumFrameInterval = CMTime(value:1,timescale:5)
        config.queueDepth = 3
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.capturesAudio = false
        let stream = SCStream(filter:filter,configuration:config,delegate:self)
        try stream.addStreamOutput(self,type:.screen,sampleHandlerQueue:queue)
        self.stream = stream
        self.config = config
        do { try await stream.startCapture() }
        catch { self.stream = nil; throw error }
    }
    @MainActor func setBending(_ active: Bool) async {
        guard let stream, let config else { return }
        config.minimumFrameInterval = CMTime(value:1,timescale:active ? 60 : 5)
        try? await stream.updateConfiguration(config)
    }
    @MainActor func stop() async {
        let old = stream; stream = nil
        try? await old?.stopCapture()
        frames.clear()
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in self?.onError?(error.localizedDescription) }
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer,createIfNecessary:false) as? [[SCStreamFrameInfo:Any]],
              let raw = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue:raw) == .complete,
              let pixelBuffer = sampleBuffer.imageBuffer else { return }
        frames.put(pixelBuffer)
        countLock.lock(); count += 1; let first = count == 1; countLock.unlock()
        if first { DispatchQueue.main.async { [weak self] in self?.onFrame?() } }
    }
}
