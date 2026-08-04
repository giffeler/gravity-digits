import CoreGraphics
import XCTest
@testable import GravityDigits

final class DisplayBoundaryTests: XCTestCase {
    func testSignedDistanceNormalsAndContainment() {
        let boundary = DisplayBoundary(size: CGSize(width: 100, height: 120))
        let radius: CGFloat = 1

        XCTAssertLessThan(boundary.signedDistance(from: CGPoint(x: 50, y: 60), particleRadius: radius), 0)
        XCTAssertTrue(boundary.contains(point: CGPoint(x: 97, y: 60), particleRadius: radius))
        XCTAssertFalse(boundary.contains(point: CGPoint(x: 98, y: 60), particleRadius: radius))

        let rightNormal = boundary.outwardNormal(at: CGPoint(x: 98, y: 60), particleRadius: radius)
        XCTAssertEqual(rightNormal.dx, 1, accuracy: 0.0001)
        XCTAssertEqual(rightNormal.dy, 0, accuracy: 0.0001)

        let cornerNormal = boundary.outwardNormal(at: CGPoint(x: 99, y: 119), particleRadius: radius)
        XCTAssertGreaterThan(cornerNormal.dx, 0)
        XCTAssertGreaterThan(cornerNormal.dy, 0)
        XCTAssertEqual(hypot(cornerNormal.dx, cornerNormal.dy), 1, accuracy: 0.0001)
    }
}

final class DigitMaskTests: XCTestCase {
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

        XCTAssertEqual(alpha, [30, 40, 10, 20])
    }

    func testObstacleBoundsEncloseExactlyTheObstaclePixels() throws {
        let mask = try XCTUnwrap(DigitMask.make(text: "12:34", size: CGSize(width: 184, height: 224)))
        let bounds = try XCTUnwrap(mask.obstacleBounds)
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

        let expected = try XCTUnwrap(sampledBounds)
        XCTAssertEqual(bounds.minX, expected.minX, accuracy: 0.0001)
        XCTAssertEqual(bounds.minY, expected.minY, accuracy: 0.0001)
        XCTAssertEqual(bounds.maxX, expected.maxX, accuracy: 0.0001)
        XCTAssertEqual(bounds.maxY, expected.maxY, accuracy: 0.0001)
    }
}

final class ParticleSystemTests: XCTestCase {
    func testSpeedClampKeepsSubstepTravelBelowMinimumRadius() {
        let maximumSubstepTravel = PerformanceConfig.maximumParticleSpeed
            * CGFloat(PerformanceConfig.fixedTimeStep)
            / CGFloat(PerformanceConfig.maximumParticleSubsteps)
        XCTAssertLessThan(maximumSubstepTravel, PerformanceConfig.minimumParticleRadius)

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
        XCTAssertLessThanOrEqual(hypot(velocity.dx, velocity.dy), PerformanceConfig.maximumParticleSpeed + 0.001)
    }

    func testEjectsParticleFromThickGlyph() throws {
        let size = CGSize(width: 184, height: 224)
        let mask = try XCTUnwrap(DigitMask.make(text: "88:88", size: size))
        let trappedPoint = try XCTUnwrap(firstObstaclePoint(in: mask))
        let system = ParticleSystem(particles: [
            Particle(position: trappedPoint, velocity: .zero, radius: 1, alpha: 1)
        ])

        system.ejectParticles(overlapping: mask, in: size)

        XCTAssertNil(mask.contactPoint(around: system.particles[0].position, radius: 1))
    }

    func testActiveParticlesStayInsideBoundaryAndOutsideMask() throws {
        let size = CGSize(width: 184, height: 224)
        let mask = try XCTUnwrap(DigitMask.make(text: "12:34", size: size))
        let system = ParticleSystem()
        system.reset(in: size, avoiding: mask)

        for particle in system.particles.prefix(system.activeParticleCount) {
            XCTAssertNil(mask.contactPoint(around: particle.position, radius: particle.radius))
        }

        system.update(
            bounds: size,
            gravity: CGVector(dx: 20_000, dy: -20_000),
            mask: mask,
            timeStep: CGFloat(PerformanceConfig.fixedTimeStep)
        )

        let boundary = DisplayBoundary(size: size)
        for particle in system.particles.prefix(system.activeParticleCount) {
            XCTAssertTrue(boundary.contains(point: particle.position, particleRadius: particle.radius))
            XCTAssertNil(mask.contactPoint(around: particle.position, radius: particle.radius))
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

final class ParticleSceneUpdateTests: XCTestCase {
    func testSceneAdvancesOnlyWhenSpriteKitCallsUpdate() {
        let scene = ParticleScene()
        scene.setSimulationPaused(false)
        scene.update(1)
        scene.update(1 + PerformanceConfig.fixedTimeStep + 0.001)
        XCTAssertEqual(scene.completedSimulationStepCount, 1)

        RunLoop.current.run(until: Date().addingTimeInterval(0.12))
        XCTAssertEqual(scene.completedSimulationStepCount, 1)
    }
}
