import CoreGraphics
import Foundation

struct Particle {
    var position: CGPoint
    var velocity: CGVector
    var radius: CGFloat
    var alpha: CGFloat
}

struct DisplayBoundary {
    let size: CGSize
    let cornerRadius: CGFloat
    let edgeInset: CGFloat

    init(size: CGSize) {
        self.size = size
        self.cornerRadius = min(size.width, size.height) * PerformanceConfig.displayCornerRadiusRatio
        self.edgeInset = PerformanceConfig.displayEdgeInset
    }

    func contains(point: CGPoint, particleRadius: CGFloat) -> Bool {
        signedDistance(from: point, particleRadius: particleRadius) <= 0
    }

    func randomPoint(particleRadius: CGFloat) -> CGPoint {
        let margin = edgeInset + particleRadius
        let minX = margin
        let maxX = max(minX, size.width - margin)
        let minY = margin
        let maxY = max(minY, size.height - margin)

        for _ in 0..<24 {
            let point = CGPoint(
                x: CGFloat.random(in: minX...maxX),
                y: CGFloat.random(in: minY...maxY)
            )
            if contains(point: point, particleRadius: particleRadius) {
                return point
            }
        }

        return CGPoint(x: size.width * 0.5, y: size.height * 0.5)
    }

    func resolve(_ particle: inout Particle) {
        let distance = signedDistance(from: particle.position, particleRadius: particle.radius)
        guard distance > 0 else { return }

        let outward = outwardNormal(at: particle.position, particleRadius: particle.radius)
        particle.position.x -= outward.dx * (distance + 0.25)
        particle.position.y -= outward.dy * (distance + 0.25)

        let velocityOutward = particle.velocity.dx * outward.dx + particle.velocity.dy * outward.dy
        if velocityOutward > 0 {
            particle.velocity.dx -= (1 + PerformanceConfig.edgeRestitution) * velocityOutward * outward.dx
            particle.velocity.dy -= (1 + PerformanceConfig.edgeRestitution) * velocityOutward * outward.dy
        }

        let normalVelocity = particle.velocity.dx * outward.dx + particle.velocity.dy * outward.dy
        let normalComponent = CGVector(dx: outward.dx * normalVelocity, dy: outward.dy * normalVelocity)
        let tangent = CGVector(
            dx: particle.velocity.dx - normalComponent.dx,
            dy: particle.velocity.dy - normalComponent.dy
        )
        particle.velocity = CGVector(
            dx: normalComponent.dx + tangent.dx * PerformanceConfig.edgeTangentialDamping,
            dy: normalComponent.dy + tangent.dy * PerformanceConfig.edgeTangentialDamping
        )
    }

    private func signedDistance(from point: CGPoint, particleRadius: CGFloat) -> CGFloat {
        let shape = insetShape(for: particleRadius)
        let localX = point.x - size.width * 0.5
        let localY = point.y - size.height * 0.5
        let qX = abs(localX) - shape.straightHalfWidth
        let qY = abs(localY) - shape.straightHalfHeight
        let outsideX = max(qX, 0)
        let outsideY = max(qY, 0)
        let outsideDistance = sqrt(outsideX * outsideX + outsideY * outsideY)
        return outsideDistance + min(max(qX, qY), 0) - shape.radius
    }

    private func outwardNormal(at point: CGPoint, particleRadius: CGFloat) -> CGVector {
        let shape = insetShape(for: particleRadius)
        let localX = point.x - size.width * 0.5
        let localY = point.y - size.height * 0.5
        let qX = abs(localX) - shape.straightHalfWidth
        let qY = abs(localY) - shape.straightHalfHeight
        let outsideX = max(qX, 0)
        let outsideY = max(qY, 0)
        let outsideLength = sqrt(outsideX * outsideX + outsideY * outsideY)

        if outsideLength > 0.0001 {
            return CGVector(
                dx: sign(localX) * outsideX / outsideLength,
                dy: sign(localY) * outsideY / outsideLength
            )
        }

        if qX > qY {
            return CGVector(dx: sign(localX), dy: 0)
        }

        return CGVector(dx: 0, dy: sign(localY))
    }

    private func insetShape(for particleRadius: CGFloat) -> (radius: CGFloat, straightHalfWidth: CGFloat, straightHalfHeight: CGFloat) {
        let margin = edgeInset + particleRadius
        let halfWidth = max(0, size.width * 0.5 - margin)
        let halfHeight = max(0, size.height * 0.5 - margin)
        let radius = min(max(0, cornerRadius - margin), halfWidth, halfHeight)
        return (
            radius: radius,
            straightHalfWidth: max(0, halfWidth - radius),
            straightHalfHeight: max(0, halfHeight - radius)
        )
    }

    private func sign(_ value: CGFloat) -> CGFloat {
        value < 0 ? -1 : 1
    }
}

final class ParticleSystem {
    private(set) var particles: [Particle] = []
    private(set) var activeParticleCount: Int

    init(count: Int = PerformanceConfig.defaultParticleCount) {
        activeParticleCount = count
    }

    func reset(in bounds: CGSize, avoiding mask: DigitMask?) {
        let boundary = DisplayBoundary(size: bounds)
        particles = []
        particles.reserveCapacity(activeParticleCount)
        for _ in 0..<activeParticleCount {
            particles.append(makeParticle(in: boundary, avoiding: mask))
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
        let boundary = DisplayBoundary(size: bounds)
        let count = min(activeParticleCount, particles.count)

        for index in 0..<count {
            var particle = particles[index]
            let previousPosition = particle.position
            particle.velocity.dx += gravity.dx * timeStep
            particle.velocity.dy += gravity.dy * timeStep
            particle.velocity.dx *= PerformanceConfig.velocityDamping
            particle.velocity.dy *= PerformanceConfig.velocityDamping

            particle.position.x += particle.velocity.dx * timeStep
            particle.position.y += particle.velocity.dy * timeStep

            boundary.resolve(&particle)
            if let mask {
                resolveGlyphCollision(&particle, previousPosition: previousPosition, mask: mask)
            }
            boundary.resolve(&particle)

            particles[index] = particle
        }
    }

    private func makeParticle(in boundary: DisplayBoundary, avoiding mask: DigitMask?) -> Particle {
        let radius = CGFloat.random(in: PerformanceConfig.minimumParticleRadius...PerformanceConfig.maximumParticleRadius)
        var position = boundary.randomPoint(particleRadius: radius)

        if let mask {
            for _ in 0..<16 where collisionPoint(for: position, radius: radius, mask: mask) != nil {
                position = boundary.randomPoint(particleRadius: radius)
            }
        }

        return Particle(
            position: position,
            velocity: CGVector(dx: CGFloat.random(in: -12...12), dy: CGFloat.random(in: -12...12)),
            radius: radius,
            alpha: CGFloat.random(in: 0.42...0.86)
        )
    }

    private func resolveGlyphCollision(_ particle: inout Particle, previousPosition: CGPoint, mask: DigitMask) {
        guard mask.mightIntersectObstacle(from: previousPosition, to: particle.position, radius: particle.radius),
              let hitPoint = collisionPoint(
                for: particle.position,
                previousPosition: previousPosition,
                radius: particle.radius,
                mask: mask
              ) else {
            return
        }

        let normal = mask.approximateNormal(point: hitPoint)
        let correctionStep = max(0.5, particle.radius * 0.55)
        var attempts = 0
        while contactPoint(around: particle.position, radius: particle.radius, mask: mask) != nil, attempts < 8 {
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
        collisionPoint(for: position, previousPosition: position, radius: radius, mask: mask)
    }

    private func collisionPoint(for position: CGPoint, previousPosition: CGPoint, radius: CGFloat, mask: DigitMask) -> CGPoint? {
        guard mask.mightIntersectObstacle(from: previousPosition, to: position, radius: radius) else {
            return nil
        }

        let sampleRadius = max(radius, 1.0)
        let deltaX = position.x - previousPosition.x
        let deltaY = position.y - previousPosition.y
        let travel = max(abs(deltaX), abs(deltaY))
        let stepCount = min(3, max(1, Int(ceil(travel / sampleRadius))))

        for step in 0...stepCount {
            let t = CGFloat(step) / CGFloat(stepCount)
            let samplePoint = CGPoint(
                x: previousPosition.x + deltaX * t,
                y: previousPosition.y + deltaY * t
            )
            if let hitPoint = contactPoint(around: samplePoint, radius: sampleRadius, mask: mask) {
                return hitPoint
            }
        }

        return nil
    }

    private func contactPoint(around position: CGPoint, radius: CGFloat, mask: DigitMask) -> CGPoint? {
        guard mask.mightIntersectObstacle(center: position, radius: radius) else {
            return nil
        }

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
