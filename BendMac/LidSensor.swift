import Foundation
import IOKit.hid

/// Public IOKit transport; Apple's lid report itself is undocumented.
/// Read-only, non-exclusive, no driver installation or root access.
final class LidSensor {
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private var device: IOHIDDevice?
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "local.jamie.BendMac.lid", qos: .userInteractive)
    var onAngle: ((Double?) -> Void)?

    init() {
        let match: [String: Any] = [kIOHIDVendorIDKey: 0x05AC, kIOHIDPrimaryUsagePageKey: 0x20, kIOHIDPrimaryUsageKey: 0x8A]
        IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)
        IOHIDManagerOpen(manager, 0)
        if let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
            device = devices.first { IOHIDDeviceOpen($0, 0) == kIOReturnSuccess }
        }
    }
    func read() -> Double? {
        guard let device else { return nil }
        var bytes = [UInt8](repeating: 0, count: 8)
        var count = bytes.count
        guard IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &bytes, &count) == kIOReturnSuccess, count >= 3 else { return nil }
        let value = Int(bytes[1]) | Int(bytes[2]) << 8
        guard (0...180).contains(value) else { return nil }
        return Double(value)
    }
    func start() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(250), leeway: .milliseconds(10))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let angle = self.read()
            DispatchQueue.main.async { [weak self] in self?.onAngle?(angle) }
        }
        self.timer = timer
        timer.resume()
    }
    func setActive(_ active: Bool) {
        timer?.schedule(deadline:.now(),repeating:.milliseconds(active ? 16 : 250),leeway:.milliseconds(active ? 2 : 10))
    }
    deinit {
        timer?.cancel()
        if let device { IOHIDDeviceClose(device, 0) }
        IOHIDManagerClose(manager, 0)
    }
}
