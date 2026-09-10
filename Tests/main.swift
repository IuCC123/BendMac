import Foundation

func check(_ value: Bool, _ message: String) { if !value { fatalError(message) } }
check(BendMath.progress(angle: 120, clearAngle: 105) == 0, "Open lid must not bend")
check(BendMath.progress(angle: 105, clearAngle: 105) == 0, "Clear threshold must be continuous")
check(BendMath.progress(angle: 12, clearAngle: 105) == 1, "Closed lid reaches full fold")
var previous = 1.0
for angle in 12...140 {
    let p = BendMath.progress(angle: Double(angle), clearAngle: 105)
    check(p >= 0 && p <= 1 && p <= previous, "Fold must be bounded and monotonic")
    previous = p
}
let one = BendMath.smooth(current: 0, target: 1, dt: 1 / 30.0)
let two = BendMath.smooth(
    current: BendMath.smooth(current: 0, target: 1, dt: 1 / 60.0), target: 1, dt: 1 / 60.0)
check(abs(one - two) < 1e-9, "Smoothing must not depend on refresh rate")
check(
    BendMath.smooth(current: 0.4, target: 0, dt: 1 / 60.0) < 0.4, "Direction changes must reverse immediately"
)
print("PASS: lid thresholds, monotonicity, frame-rate independence, reversal")
