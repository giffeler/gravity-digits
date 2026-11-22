import CoreGraphics
import SpriteKit
import Synchronization
import Foundation
import Testing
@testable import GravityDigits

struct DisplayBoundaryTests {
    @Test
    func testSignedDistanceNormalsAndContainment() {
        let boundary = DisplayBoundary(size: CGSize(width: 100, height: 120))
        let radius: CGFloat = 1

        #expect(boundary.signedDistance(from: CGPoint(x: 50, y: 60), particleRadius: radius) < 0)
        #expect(boundary.contains(point: CGPoint(x: 97, y: 60), particleRadius: radius))
        #expect(!boundary.contains(point: CGPoint(x: 98, y: 60), particleRadius: radius))

        let rightNormal = boundary.outwardNormal(at: CGPoint(x: 98, y: 60), particleRadius: radius)
        #expect(abs(rightNormal.dx - 1) <= 0.0001)
        #expect(abs(rightNormal.dy - 0) <= 0.0001)

        let cornerNormal = boundary.outwardNormal(at: CGPoint(x: 99, y: 119), particleRadius: radius)
        #expect(cornerNormal.dx > 0)
        #expect(cornerNormal.dy > 0)
        #expect(abs(hypot(cornerNormal.dx, cornerNormal.dy) - 1) <= 0.0001)
    }
}

struct DigitMaskTests {
    @Test
    func testSceneAlphaRowsAreFlipped() {
        var rgba = [UInt8](repeating: 0, count: 16)
        rgba[3] = 10
        rgba[7] = 20
        rgba[11] = 30
        rgba[15] = 40

        let alpha = rgba.withUnsafeBufferPointer { buffer in
            DigitMask.sceneAlphaBytes(
                from: buffer.baseAddress,
                pixelWidth: 2,
                pixelHeight: 2,
                bytesPerRow: 8
            )
        }

        #expect(alpha == [30, 40, 10, 20])
    }

    @Test
    func testObstacleBoundsEncloseExactlyTheObstaclePixels() throws {
        let mask = try #require(DigitMask.make(text: "12:34", size: CGSize(width: 184, height: 224)))
        let bounds = try #require(mask.obstacleBounds)
        var sampledBounds: CGRect?
        let pixelSize = 1.0 / mask.scale

        for y in stride(from: pixelSize * 0.5, to: mask.size.height, by: pixelSize) {
            for x in stride(from: pixelSize * 0.5, to: mask.size.width, by: pixelSize) {
                let point = CGPoint(x: x, y: y)
                guard mask.isObstacle(point: point) else { continue }
                let pixelRect = CGRect(
                    x: x - pixelSize * 0.5,
                    y: y - pixelSize * 0.5,
                    width: pixelSize,
                    height: pixelSize
                )
                sampledBounds = sampledBounds?.union(pixelRect) ?? pixelRect
            }
        }

        let expected = try #require(sampledBounds)
        #expect(abs(bounds.minX - expected.minX) <= 0.0001)
        #expect(abs(bounds.minY - expected.minY) <= 0.0001)
        #expect(abs(bounds.maxX - expected.maxX) <= 0.0001)
        #expect(abs(bounds.maxY - expected.maxY) <= 0.0001)
    }
}

struct ParticleSystemTests {
    @Test
    func testResetAllocatesOnlyTheMaximumActiveParticleCount() {
        let system = ParticleSystem()
        system.reset(in: CGSize(width: 184, height: 224), avoiding: nil)

        #expect(system.particles.count == PerformanceConfig.maximumParticleCount)
        #expect(system.activeParticleCount == PerformanceConfig.defaultParticleCount)
    }

    @Test
    func testSpeedClampKeepsSubstepTravelBelowMinimumRadius() {
        let maximumSubstepTravel = PerformanceConfig.maximumParticleSpeed
            * CGFloat(PerformanceConfig.fixedTimeStep)
            / CGFloat(PerformanceConfig.maximumParticleSubsteps)
        #expect(maximumSubstepTravel < PerformanceConfig.minimumParticleRadius)

        let system = ParticleSystem(particles: [
            Particle(
                position: CGPoint(x: 100, y: 100),
                velocity: .zero,
                radius: PerformanceConfig.minimumParticleRadius,
                alpha: 1
            )
        ])
        system.update(
            bounds: CGSize(width: 200, height: 200),
            gravity: CGVector(dx: PerformanceConfig.maximumParticleSpeed * 100, dy: 0),
            mask: nil,
            timeStep: CGFloat(PerformanceConfig.fixedTimeStep)
        )

        let velocity = system.particles[0].velocity
        #expect(hypot(velocity.dx, velocity.dy) <= PerformanceConfig.maximumParticleSpeed + 0.001)
    }

    @Test
    func testEjectsParticleFromThickGlyph() throws {
        let size = CGSize(width: 184, height: 224)
        let mask = try #require(DigitMask.make(text: "88:88", size: size))
        let trappedPoint = try #require(firstObstaclePoint(in: mask))
        let system = ParticleSystem(particles: [
            Particle(position: trappedPoint, velocity: .zero, radius: 1, alpha: 1)
        ])

        let relocatedIndices = system.ejectParticles(overlapping: mask, in: size)

        #expect(relocatedIndices == [0])
        #expect(mask.contactPoint(around: system.particles[0].position, radius: 1) == nil)
    }

    @Test
    func testReactivatedParticlesGetFreshSafePositions() throws {
        let size = CGSize(width: 184, height: 224)
        let mask = try #require(DigitMask.make(text: "12:34", size: size))
        let system = ParticleSystem()
        system.reset(in: size, avoiding: mask)
        system.setActiveParticleCount(PerformanceConfig.minimumParticleCount)

        let oldCount = system.activeParticleCount
        let activatedRange = system.activateParticles(
            upTo: oldCount + PerformanceConfig.adaptiveRecoveryStep,
            in: size,
            avoiding: mask
        )

        #expect(activatedRange == oldCount..<(oldCount + PerformanceConfig.adaptiveRecoveryStep))
        for particle in system.particles[activatedRange] {
            #expect(mask.contactPoint(around: particle.position, radius: particle.radius) == nil)
        }
    }

    @Test
    func testActiveParticlesStayInsideBoundaryAndOutsideMask() throws {
        let size = CGSize(width: 184, height: 224)
        let mask = try #require(DigitMask.make(text: "12:34", size: size))
        let system = ParticleSystem()
        system.reset(in: size, avoiding: mask)

        for particle in system.particles.prefix(system.activeParticleCount) {
            #expect(mask.contactPoint(around: particle.position, radius: particle.radius) == nil)
        }

        system.update(
            bounds: size,
            gravity: CGVector(dx: 20_000, dy: -20_000),
            mask: mask,
            timeStep: CGFloat(PerformanceConfig.fixedTimeStep)
        )

        let boundary = DisplayBoundary(size: size)
        for particle in system.particles.prefix(system.activeParticleCount) {
            #expect(boundary.contains(point: particle.position, particleRadius: particle.radius))
            #expect(mask.contactPoint(around: particle.position, radius: particle.radius) == nil)
        }
    }

    private func firstObstaclePoint(in mask: DigitMask) -> CGPoint? {
        guard let bounds = mask.obstacleBounds else { return nil }
        let pixelSize = 1.0 / mask.scale
        for y in stride(from: bounds.minY + pixelSize * 0.5, to: bounds.maxY, by: pixelSize) {
            for x in stride(from: bounds.minX + pixelSize * 0.5, to: bounds.maxX, by: pixelSize) {
                let point = CGPoint(x: x, y: y)
                if mask.isObstacle(point: point) {
                    return point
                }
            }
        }
        return nil
    }
}

struct ParticleSceneUpdateTests {
    @Test
    func testFrameCallbackCanRunOffMainActor() throws {
        let result = Mutex<(onMainThread: Bool, steps: Int)?>(nil)
        let completed = DispatchGroup()
        DispatchQueue.global().async(group: completed) {
            let scene = ParticleScene()
            scene.update(1)
            scene.update(1 + PerformanceConfig.fixedTimeStep + 0.001)
            result.withLock { $0 = (Thread.isMainThread, scene.completedSimulationStepCount) }
        }
        try #require(completed.wait(timeout: .now() + 5) == .success)
        let frame = try #require(result.withLock { $0 })
        #expect(!frame.onMainThread)
        #expect(frame.steps == 1)
    }

    @Test
    func testSceneAdvancesOnlyWhenSpriteKitCallsUpdate() {
        let scene = ParticleScene()
        scene.setSimulationPaused(false)
        scene.update(1)
        scene.update(1 + PerformanceConfig.fixedTimeStep + 0.001)
        #expect(scene.completedSimulationStepCount == 1)

        RunLoop.current.run(until: Date().addingTimeInterval(0.12))
        #expect(scene.completedSimulationStepCount == 1)
    }

    @Test
    func testSceneLimitsCatchUpWorkAfterLongFrame() {
        let scene = ParticleScene()
        scene.setSimulationPaused(false)
        scene.update(1)
        scene.update(1 + PerformanceConfig.maxAccumulatedTime)

        #expect(scene.completedSimulationStepCount == PerformanceConfig.maximumSimulationStepsPerFrame)
    }
}

struct MaskMailboxTests {
    @Test
    func testOlderCompletionCannotOverwriteNewerResult() throws {
        let mailbox = ParticleScene.MaskMailbox()
        mailbox.publish(.init(generation: 2, key: "12:35", size: .zero, mask: nil))
        mailbox.publish(.init(generation: 1, key: "12:34", size: .zero, mask: nil))

        let result = try #require(mailbox.take())
        #expect(result.generation == 2)
        #expect(result.key == "12:35")
        #expect(mailbox.take() == nil)
    }
}

private final class MaskObservations: Sendable {
    let times = Mutex<[String]>([])
    let date = Mutex(Date(timeIntervalSince1970: 0))
}

@MainActor
struct MaskHandoffTests {
    private let size = CGSize(width: 184, height: 224)

    @Test
    func testCompletedMaskWaitsForActiveFrame() throws {
        let queue = DispatchQueue(label: "GravityDigitsTests.mask")
        let scene = ParticleScene(maskBuildQueue: queue, currentDate: { Date(timeIntervalSince1970: 0) })
        let motion = MotionManager()
        let observations = MaskObservations()
        scene.onTimeTextChanged = { text in observations.times.withLock { $0.append(text) } }
        scene.configure(size: size, motionManager: motion)
        queue.sync {}

        let digit = try #require(scene.children.compactMap { $0 as? SKSpriteNode }.first)
        #expect(digit.texture == nil)
        #expect(observations.times.withLock { $0.isEmpty })
        scene.setSimulationPaused(true)
        scene.update(1)
        #expect(digit.texture == nil)
        #expect(scene.completedSimulationStepCount == 0)

        scene.setSimulationPaused(false)
        scene.update(2)
        #expect(digit.texture != nil)
        #expect(digit.size == size)
        #expect(observations.times.withLock { $0.count } == 1)
        scene.update(2 + PerformanceConfig.fixedTimeStep + 0.001)
        #expect(observations.times.withLock { $0.count } == 1)
    }

    @Test
    func testResizeRejectsCompletedMaskFromOldSize() throws {
        let queue = DispatchQueue(label: "GravityDigitsTests.resize")
        let scene = ParticleScene(maskBuildQueue: queue, currentDate: { Date(timeIntervalSince1970: 0) })
        let motion = MotionManager()
        let observations = MaskObservations()
        scene.onTimeTextChanged = { text in observations.times.withLock { $0.append(text) } }
        scene.configure(size: size, motionManager: motion)
        queue.sync {}

        let resized = CGSize(width: 198, height: 242)
        queue.suspend()
        scene.configure(size: resized, motionManager: motion)
        scene.update(1)
        let displayedBeforeNewMask = observations.times.withLock { $0.count }
        queue.resume()
        #expect(displayedBeforeNewMask == 0)
        queue.sync {}
        scene.update(2)

        let digit = try #require(scene.children.compactMap { $0 as? SKSpriteNode }.first)
        #expect(digit.texture != nil)
        #expect(digit.size == resized)
        #expect(observations.times.withLock { $0.count } == 1)
    }

    @Test
    func testMinuteChangeRejectsCompletedMaskFromPreviousMinute() {
        let queue = DispatchQueue(label: "GravityDigitsTests.minute")
        let observations = MaskObservations()
        let scene = ParticleScene(maskBuildQueue: queue, currentDate: { observations.date.withLock { $0 } })
        let motion = MotionManager()
        scene.onTimeTextChanged = { text in observations.times.withLock { $0.append(text) } }
        scene.configure(size: size, motionManager: motion)
        queue.sync {}

        observations.date.withLock { $0 = $0.addingTimeInterval(60) }
        scene.update(1)
        #expect(observations.times.withLock { $0.isEmpty })
        queue.sync {}
        scene.update(2)

        let components = Calendar.current.dateComponents([.hour, .minute], from: observations.date.withLock { $0 })
        let expected = String(format: "%02d:%02d", components.hour!, components.minute!)
        #expect(observations.times.withLock { $0 } == [expected])
    }
}
