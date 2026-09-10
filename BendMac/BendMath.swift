import Foundation

/// Blur-led motion: the physical lid supplies most of the rotation.
/// Work in screen-height units so Retina scaling does not alter the fold.
enum BendMath {
    static func progress(angle: Double, clearAngle: Double) -> Double {
        let t = min(1, max(0, (clearAngle - angle) / max(1, clearAngle - 12)))
        return t * t * (3 - 2 * t)
    }
    static func smooth(current: Double, target: Double, dt: Double) -> Double {
        let next = current + (target - current) * (1 - exp(-min(dt, 0.1) / 0.075))
        return abs(next - target) < 0.0001 ? target : next
    }
}
