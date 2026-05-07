import CoreGraphics
import Foundation

struct Particle {
    var position: CGPoint
    var velocity: CGVector
    var radius: CGFloat
    var alpha: CGFloat
}

final class ParticleSystem {
    private(set) var particles: [Particle] = []
    private(set) var activeParticleCount: Int

    init(count: Int = PerformanceConfig.defaultParticleCount) {
        activeParticleCount = count
    }

    func reset(in bounds: CGSize, avoiding mask: DigitMask?) {
        particles = []
        particles.reserveCapacity(activeParticleCount)
        for _ in 0..<activeParticleCount {
            particles.append(makeParticle(in: bounds, avoiding: mask))
        }
        activeParticleCount = min(activeParticleCount, particles.count)
    }

    func setActiveParticleCount(_ count: Int) {
        activeParticleCount = max(
            PerformanceConfig.minimumParticleCount,
            min(count, min(PerformanceConfig.maximumParticleCount, particles.count))
        )
    }

    func update(bounds: CGSize, gravity: CGVector, mask: DigitMask?, timeStep: CGFloat) {
        guard bounds.width > 1, bounds.height > 1 else { return }
        let count = min(activeParticleCount, particles.count)

        for index in 0..<count {
            var particle = particles[index]
            particle.velocity.dx += gravity.dx * timeStep
            particle.velocity.dy += gravity.dy * timeStep
            particle.velocity.dx *= PerformanceConfig.velocityDamping
            particle.velocity.dy *= PerformanceConfig.velocityDamping

            particle.position.x += particle.velocity.dx * timeStep
            particle.position.y += particle.velocity.dy * timeStep

            resolveEdgeCollision(&particle, bounds: bounds)
            if let mask {
                resolveGlyphCollision(&particle, mask: mask)
            }

            particles[index] = particle
        }
    }

    private func makeParticle(in bounds: CGSize, avoiding mask: DigitMask?) -> Particle {
        let radius = CGFloat.random(in: PerformanceConfig.minimumParticleRadius...PerformanceConfig.maximumParticleRadius)
        var position = CGPoint(x: CGFloat.random(in: radius...max(radius, bounds.width - radius)),
                               y: CGFloat.random(in: radius...max(radius, bounds.height - radius)))

        if let mask {
            for _ in 0..<16 where collisionPoint(for: position, radius: radius, mask: mask) != nil {
                position = CGPoint(x: CGFloat.random(in: radius...max(radius, bounds.width - radius)),
                                   y: CGFloat.random(in: radius...max(radius, bounds.height - radius)))
            }
        }

        return Particle(
            position: position,
            velocity: CGVector(dx: CGFloat.random(in: -12...12), dy: CGFloat.random(in: -12...12)),
            radius: radius,
            alpha: CGFloat.random(in: 0.42...0.86)
        )
    }

    private func resolveEdgeCollision(_ particle: inout Particle, bounds: CGSize) {
        let radius = particle.radius
        if particle.position.x < radius {
            particle.position.x = radius
            particle.velocity.dx = abs(particle.velocity.dx) * PerformanceConfig.edgeRestitution
            particle.velocity.dy *= 0.88
        } else if particle.position.x > bounds.width - radius {
            particle.position.x = bounds.width - radius
            particle.velocity.dx = -abs(particle.velocity.dx) * PerformanceConfig.edgeRestitution
            particle.velocity.dy *= 0.88
        }

        if particle.position.y < radius {
            particle.position.y = radius
            particle.velocity.dy = abs(particle.velocity.dy) * PerformanceConfig.edgeRestitution
            particle.velocity.dx *= 0.88
        } else if particle.position.y > bounds.height - radius {
            particle.position.y = bounds.height - radius
            particle.velocity.dy = -abs(particle.velocity.dy) * PerformanceConfig.edgeRestitution
            particle.velocity.dx *= 0.88
        }
    }

    private func resolveGlyphCollision(_ particle: inout Particle, mask: DigitMask) {
        guard let hitPoint = collisionPoint(for: particle.position, radius: particle.radius, mask: mask) else {
            return
        }

        let normal = mask.approximateNormal(point: hitPoint)
        let correctionStep = max(0.5, particle.radius * 0.55)
        var attempts = 0
        while collisionPoint(for: particle.position, radius: particle.radius, mask: mask) != nil, attempts < 10 {
            particle.position.x += normal.dx * correctionStep
            particle.position.y += normal.dy * correctionStep
            attempts += 1
        }

        let velocityIntoNormal = dot(particle.velocity, normal)
        if velocityIntoNormal < 0 {
            particle.velocity.dx -= (1 + PerformanceConfig.glyphRestitution) * velocityIntoNormal * normal.dx
            particle.velocity.dy -= (1 + PerformanceConfig.glyphRestitution) * velocityIntoNormal * normal.dy
        }

        let normalVelocity = dot(particle.velocity, normal)
        let normalComponent = CGVector(dx: normal.dx * normalVelocity, dy: normal.dy * normalVelocity)
        let tangent = CGVector(dx: particle.velocity.dx - normalComponent.dx, dy: particle.velocity.dy - normalComponent.dy)
        particle.velocity = CGVector(
            dx: normalComponent.dx + tangent.dx * PerformanceConfig.glyphTangentialDamping,
            dy: normalComponent.dy + tangent.dy * PerformanceConfig.glyphTangentialDamping
        )
    }

    private func collisionPoint(for position: CGPoint, radius: CGFloat, mask: DigitMask) -> CGPoint? {
        if mask.isObstacle(point: position) {
            return position
        }

        let sampleRadius = max(radius, 1.0)
        let right = CGPoint(x: position.x + sampleRadius, y: position.y)
        if mask.isObstacle(point: right) { return right }

        let left = CGPoint(x: position.x - sampleRadius, y: position.y)
        if mask.isObstacle(point: left) { return left }

        let up = CGPoint(x: position.x, y: position.y + sampleRadius)
        if mask.isObstacle(point: up) { return up }

        let down = CGPoint(x: position.x, y: position.y - sampleRadius)
        if mask.isObstacle(point: down) { return down }

        return nil
    }

    private func dot(_ vector: CGVector, _ normal: CGVector) -> CGFloat {
        vector.dx * normal.dx + vector.dy * normal.dy
    }
}
