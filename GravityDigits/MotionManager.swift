import CoreGraphics
import CoreMotion
import Foundation

final class MotionManager: ObservableObject {
    private let motionManager = CMMotionManager()
    private var fallbackTimer: Timer?
    private var smoothedUnitGravity = CGVector(dx: 0, dy: -1)
    private let smoothing: CGFloat = 0.16

    private(set) var isUsingFallback = true

    var gravityVector: CGVector {
        let unit = clamped(smoothedUnitGravity, maxMagnitude: PerformanceConfig.maxGravityMagnitude)
        return CGVector(
            dx: unit.dx * PerformanceConfig.gravityScale,
            dy: unit.dy * PerformanceConfig.gravityScale
        )
    }

    func start() {
        stopFallbackTimer()

        #if targetEnvironment(simulator)
        startFallbackTimer(animated: true)
        return
        #else
        guard motionManager.isAccelerometerAvailable else {
            startFallbackTimer(animated: false)
            return
        }

        isUsingFallback = false
        motionManager.accelerometerUpdateInterval = 1.0 / 30.0
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self, let acceleration = data?.acceleration else { return }
            self.ingestAccelerometer(x: acceleration.x, y: acceleration.y)
        }
        #endif
    }

    func stop() {
        motionManager.stopAccelerometerUpdates()
        stopFallbackTimer()
    }

    private func ingestAccelerometer(x: Double, y: Double) {
        let mapped = CGVector(dx: CGFloat(x), dy: CGFloat(y))
        smoothedUnitGravity = lowPass(previous: smoothedUnitGravity, next: mapped)
    }

    private func startFallbackTimer(animated: Bool) {
        isUsingFallback = true
        if !animated {
            smoothedUnitGravity = CGVector(dx: 0, dy: -1)
            return
        }

        let startDate = Date()
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let elapsed = Date().timeIntervalSince(startDate)
            let angle = CGFloat(elapsed * 0.45) - (.pi / 2.0)
            let animatedVector = CGVector(dx: cos(angle) * 0.65, dy: sin(angle))
            self.smoothedUnitGravity = self.lowPass(previous: self.smoothedUnitGravity, next: animatedVector)
        }
    }

    private func stopFallbackTimer() {
        fallbackTimer?.invalidate()
        fallbackTimer = nil
    }

    private func lowPass(previous: CGVector, next: CGVector) -> CGVector {
        CGVector(
            dx: previous.dx + (next.dx - previous.dx) * smoothing,
            dy: previous.dy + (next.dy - previous.dy) * smoothing
        )
    }

    private func clamped(_ vector: CGVector, maxMagnitude: CGFloat) -> CGVector {
        let magnitude = sqrt(vector.dx * vector.dx + vector.dy * vector.dy)
        guard magnitude > maxMagnitude, magnitude > 0 else { return vector }
        let scale = maxMagnitude / magnitude
        return CGVector(dx: vector.dx * scale, dy: vector.dy * scale)
    }
}
