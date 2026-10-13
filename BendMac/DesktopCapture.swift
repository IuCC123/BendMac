import CoreMedia
import ScreenCaptureKit

enum CaptureError: LocalizedError {
    case overlayUnavailable

    var errorDescription: String? {
        "BendMac could not keep its fold out of screen capture."
    }
}

final class DesktopCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    /// The overlay layer must be tagged with this space, or the fold shifts the desktop's colors.
    static let colorSpace = CGColorSpace.displayP3
    let frames: FrameStore
    @MainActor private var stream: SCStream?
    @MainActor private var config: SCStreamConfiguration?
    private let queue = DispatchQueue(label: "local.jamie.BendMac.capture", qos: .userInteractive)
    var onError: ((Error) -> Void)?
    var onFirstFrame: (() -> Void)?
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

    @MainActor func start(displayID: CGDirectDisplayID, excludingWindow overlayID: CGWindowID) async throws {
        generation += 1
        let request = generation
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard request == generation else { throw CancellationError() }
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw NSError(domain: "The built-in display is unavailable.", code: 1)
        }
        // Never start an unfiltered stream: the overlay would capture its own output.
        guard let overlay = content.windows.first(where: { $0.windowID == overlayID }) else {
            throw CaptureError.overlayUnavailable
        }
        // Only the overlay is excluded, so BendMac's Settings window bends with the desktop.
        let filter = SCContentFilter(display: display, excludingWindows: [overlay])
        let config = SCStreamConfiguration()
        // Use the display mode's backing resolution for Retina capture.
        let mode = CGDisplayCopyDisplayMode(displayID)
        config.width = mode?.pixelWidth ?? CGDisplayPixelsWide(displayID)
        config.height = mode?.pixelHeight ?? CGDisplayPixelsHigh(displayID)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 5)
        config.queueDepth = 3
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = Self.colorSpace
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
            do { try await stream.updateConfiguration(config) } catch {
                if self.stream === stream {
                    onError?(error)
                    return
                }
                // An obsolete stream must not discard a newer stream's pending rate change.
                continue
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
            self.onError?(error)
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
        let firstFrame = frames.get() == nil
        frames.put(pixelBuffer, displayTime: attachments.first?[.displayTime] as? UInt64 ?? 0)
        if firstFrame {
            Task { @MainActor [weak self] in
                guard let self, self.stream === stream else { return }
                self.onFirstFrame?()
            }
        }
        count += 1
    }
}
