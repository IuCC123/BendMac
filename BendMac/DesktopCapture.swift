import CoreMedia
import ScreenCaptureKit

final class DesktopCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    let frames: FrameStore
    @MainActor private var stream: SCStream?
    @MainActor private var config: SCStreamConfiguration?
    private let queue = DispatchQueue(label: "local.jamie.BendMac.capture", qos: .userInteractive)
    var onError: ((String) -> Void)?
    private let countLock = NSLock()
    private var count = 0
    private var outputStream: SCStream?
    @MainActor private var generation = 0
    @MainActor private var desiredBending = false
    @MainActor private var updatingRate = false
    var frameCount: Int {
        countLock.lock()
        defer { countLock.unlock() }
        return count
    }
    init(frames: FrameStore) { self.frames = frames }

    @MainActor func start(displayID: CGDirectDisplayID) async throws {
        generation += 1
        let request = generation
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard request == generation else { throw CancellationError() }
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw NSError(domain: "The built-in display is unavailable.", code: 1)
        }
        let ownApp = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        // Exclude our entire process to prevent recursive capture of the overlay and settings.
        let filter = SCContentFilter(display: display, excludingApplications: ownApp, exceptingWindows: [])
        let config = SCStreamConfiguration()
        // CGDisplayPixelsWide reports points; capture the backing pixels so Retina text stays sharp.
        let mode = CGDisplayCopyDisplayMode(displayID)
        config.width = mode?.pixelWidth ?? CGDisplayPixelsWide(displayID)
        config.height = mode?.pixelHeight ?? CGDisplayPixelsHigh(displayID)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 5)
        config.queueDepth = 3
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.capturesAudio = false
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        self.stream = stream
        self.config = config
        desiredBending = false
        acceptOutput(from: stream)
        do {
            try await stream.startCapture()
            guard request == generation else {
                try? await stream.stopCapture()
                throw CancellationError()
            }
        } catch {
            if self.stream === stream {
                self.stream = nil
                self.config = nil
                acceptOutput(from: nil)
            }
            throw error
        }
    }
    @MainActor func setBending(_ active: Bool) async {
        desiredBending = active
        guard !updatingRate else { return }
        updatingRate = true
        defer { updatingRate = false }
        while let stream, let config {
            let requested = desiredBending
            config.minimumFrameInterval = CMTime(value: 1, timescale: requested ? 60 : 5)
            do { try await stream.updateConfiguration(config) }
            catch {
                if self.stream === stream { onError?(error.localizedDescription) }
                return
            }
            if self.stream === stream && requested == desiredBending { return }
        }
    }
    @MainActor func stop() async {
        generation += 1
        let old = stream
        stream = nil
        config = nil
        acceptOutput(from: nil)
        try? await old?.stopCapture()
    }
    private func acceptOutput(from stream: SCStream?) {
        countLock.lock()
        defer { countLock.unlock() }
        outputStream = stream
        frames.clear()
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self, self.stream === stream else { return }
            self.onError?(error.localizedDescription)
        }
    }
    func stream(
        _ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType
    ) {
        guard type == .screen, sampleBuffer.isValid,
            let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
            let raw = attachments.first?[.status] as? Int,
            SCFrameStatus(rawValue: raw) == .complete,
            let pixelBuffer = sampleBuffer.imageBuffer
        else { return }
        countLock.lock()
        defer { countLock.unlock() }
        guard outputStream === stream else { return }
        frames.put(pixelBuffer)
        count += 1
    }
}
