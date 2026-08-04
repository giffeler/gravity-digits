import CoreGraphics
import Foundation

struct Particle {
    var position: CGPoint
    var velocity: CGVector
    var radius: CGFloat
    var alpha: CGFloat
}

final class DisplayBoundary {
    private struct InsetShape {
        let radius: CGFloat
        let straightHalfWidth: CGFloat
        let straightHalfHeight: CGFloat
    }

    let size: CGSize
    let cornerRadius: CGFloat
    let edgeInset: CGFloat
    private var insetShapeCache: [CGFloat: InsetShape] = [:]

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

    private func insetShape(for particleRadius: CGFloat) -> InsetShape {
        if let cached = insetShapeCache[particleRadius] {
            return cached
        }

        let margin = edgeInset + particleRadius
        let halfWidth = max(0, size.width * 0.5 - margin)
        let halfHeight = max(0, size.height * 0.5 - margin)
        let radius = min(max(0, cornerRadius - margin), halfWidth, halfHeight)
        let shape = InsetShape(
            radius: radius,
            straightHalfWidth: max(0, halfWidth - radius),
            straightHalfHeight: max(0, halfHeight - radius)
        )
        insetShapeCache[particleRadius] = shape
        return shape
    }

    private func sign(_ value: CGFloat) -> CGFloat {
        value < 0 ? -1 : 1
    }
}

final class ParticleSystem {
    private(set) var particles: [Particle] = []
    private(set) var activeParticleCount: Int
    private var displayBoundary: DisplayBoundary?

    init(count: Int = PerformanceConfig.defaultParticleCount) {
        activeParticleCount = count
    }

    func reset(in bounds: CGSize, avoiding mask: DigitMask?) {
        let boundary = DisplayBoundary(size: bounds)
        displayBoundary = boundary
        particles = []
        particles.reserveCapacity(PerformanceConfig.maximumParticleCount)
        for _ in 0..<PerformanceConfig.maximumParticleCount {
            particles.append(makeParticle(in: boundary, avoiding: mask))
        }
    }

    func setActiveParticleCount(_ count: Int) {
        activeParticleCount = max(
            PerformanceConfig.minimumParticleCount,
            min(count, min(PerformanceConfig.maximumParticleCount, particles.count))
        )
    }

    var totalKineticEnergy: CGFloat {
        let count = min(activeParticleCount, particles.count)
        guard count > 0 else { return 0 }
        return particles[..<count].reduce(CGFloat.zero) { result, particle in
            let speedSquared = particle.velocity.dx * particle.velocity.dx
                + particle.velocity.dy * particle.velocity.dy
            return result + 0.5 * speedSquared
        }
    }

    func update(bounds: CGSize, gravity: CGVector, mask: DigitMask?, timeStep: CGFloat) {
        guard bounds.width > 1, bounds.height > 1 else { return }
        let boundary = boundary(for: bounds)
        let count = min(activeParticleCount, particles.count)

        for index in 0..<count {
            var particle = particles[index]
            particle.velocity.dx += gravity.dx * timeStep
            particle.velocity.dy += gravity.dy * timeStep
            particle.velocity.dx *= PerformanceConfig.velocityDamping
            particle.velocity.dy *= PerformanceConfig.velocityDamping
            clampVelocity(&particle.velocity)

            moveParticle(&particle, boundary: boundary, mask: mask, timeStep: timeStep)

            particles[index] = particle
        }
    }

    func ejectParticles(overlapping mask: DigitMask, in bounds: CGSize) {
        guard bounds.width > 1, bounds.height > 1 else { return }
        let boundary = boundary(for: bounds)

        for index in particles.indices {
            var particle = particles[index]
            guard contactPoint(around: particle.position, radius: particle.radius, mask: mask) != nil,
                  let freePosition = nearestFreePosition(
                    from: particle.position,
                    radius: particle.radius,
                    boundary: boundary,
                    mask: mask
                  ) else {
                continue
            }

            particle.position = freePosition
            boundary.resolve(&particle)
            particles[index] = particle
        }
    }

    private func moveParticle(_ particle: inout Particle, boundary: DisplayBoundary, mask: DigitMask?, timeStep: CGFloat) {
        let delta = CGVector(dx: particle.velocity.dx * timeStep, dy: particle.velocity.dy * timeStep)
        let travel = sqrt(delta.dx * delta.dx + delta.dy * delta.dy)
        let targetStepDistance = max(PerformanceConfig.minimumParticleStepDistance, particle.radius * 0.75)
        let stepCount = min(
            PerformanceConfig.maximumParticleSubsteps,
            max(1, Int((travel / targetStepDistance).rounded(.up)))
        )
        let stepDelta = CGVector(dx: delta.dx / CGFloat(stepCount), dy: delta.dy / CGFloat(stepCount))

        for _ in 0..<stepCount {
            let previousPosition = particle.position
            particle.position.x += stepDelta.dx
            particle.position.y += stepDelta.dy

            boundary.resolve(&particle)
            if let mask {
                resolveGlyphCollision(
                    &particle,
                    previousPosition: previousPosition,
                    boundary: boundary,
                    mask: mask
                )
            }
            boundary.resolve(&particle)
        }
    }

    private func makeParticle(in boundary: DisplayBoundary, avoiding mask: DigitMask?) -> Particle {
        let radius = CGFloat.random(in: PerformanceConfig.minimumParticleRadius...PerformanceConfig.maximumParticleRadius)
        var position = boundary.randomPoint(particleRadius: radius)

        if let mask {
            for _ in 0..<16 where collisionPoint(for: position, radius: radius, mask: mask) != nil {
                position = boundary.randomPoint(particleRadius: radius)
            }
            if collisionPoint(for: position, radius: radius, mask: mask) != nil,
               let freePosition = nearestFreePosition(
                from: position,
                radius: radius,
                boundary: boundary,
                mask: mask
               ) {
                position = freePosition
            }
        }

        return Particle(
            position: position,
            velocity: CGVector(dx: CGFloat.random(in: -12...12), dy: CGFloat.random(in: -12...12)),
            radius: radius,
            alpha: CGFloat.random(in: 0.42...0.86)
        )
    }

    private func resolveGlyphCollision(
        _ particle: inout Particle,
        previousPosition: CGPoint,
        boundary: DisplayBoundary,
        mask: DigitMask
    ) {
        guard let hitPoint = collisionPoint(
            for: particle.position,
            previousPosition: previousPosition,
            radius: particle.radius,
            mask: mask
        ) else {
            return
        }

        let collisionPosition = particle.position
        if let freePosition = nearestFreePosition(
            from: collisionPosition,
            radius: particle.radius,
            boundary: boundary,
            mask: mask
        ) {
            particle.position = freePosition
        }

        let correction = CGVector(
            dx: particle.position.x - collisionPosition.x,
            dy: particle.position.y - collisionPosition.y
        )
        let normal = normalized(correction) ?? mask.approximateNormal(point: hitPoint)

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
        let travel = sqrt(deltaX * deltaX + deltaY * deltaY)
        let stepDistance = max(PerformanceConfig.minimumGlyphSweepStepDistance, sampleRadius * 0.5)
        let stepCount = min(
            PerformanceConfig.maximumGlyphSweepSteps,
            max(1, Int((travel / stepDistance).rounded(.up)))
        )
        var lastClearPoint = previousPosition

        for step in 0...stepCount {
            let t = CGFloat(step) / CGFloat(stepCount)
            let samplePoint = CGPoint(
                x: previousPosition.x + deltaX * t,
                y: previousPosition.y + deltaY * t
            )
            if let hitPoint = contactPoint(around: samplePoint, radius: sampleRadius, mask: mask) {
                return refinedContactPoint(
                    from: lastClearPoint,
                    to: samplePoint,
                    endHit: hitPoint,
                    radius: sampleRadius,
                    mask: mask
                )
            }
            lastClearPoint = samplePoint
        }

        return nil
    }

    private func refinedContactPoint(
        from start: CGPoint,
        to end: CGPoint,
        endHit: CGPoint,
        radius: CGFloat,
        mask: DigitMask
    ) -> CGPoint {
        var low = start
        var high = end
        var hitPoint = endHit

        for _ in 0..<5 {
            let midpoint = CGPoint(x: (low.x + high.x) * 0.5, y: (low.y + high.y) * 0.5)
            if let midpointHit = contactPoint(around: midpoint, radius: radius, mask: mask) {
                high = midpoint
                hitPoint = midpointHit
            } else {
                low = midpoint
            }
        }

        return hitPoint
    }

    private func contactPoint(around position: CGPoint, radius: CGFloat, mask: DigitMask) -> CGPoint? {
        mask.contactPoint(around: position, radius: radius)
    }

    private func nearestFreePosition(
        from origin: CGPoint,
        radius: CGFloat,
        boundary: DisplayBoundary,
        mask: DigitMask
    ) -> CGPoint? {
        if boundary.contains(point: origin, particleRadius: radius),
           contactPoint(around: origin, radius: radius, mask: mask) == nil {
            return origin
        }

        let ringSpacing = 1.0 / mask.scale
        let maximumDistance = hypot(boundary.size.width, boundary.size.height)
        let ringCount = Int((maximumDistance / ringSpacing).rounded(.up))

        for ring in 1...ringCount {
            let distance = CGFloat(ring) * ringSpacing
            let sampleCount = max(8, Int((2.0 * .pi * distance / ringSpacing).rounded(.up)))
            for sample in 0..<sampleCount {
                let angle = CGFloat(sample) * 2.0 * .pi / CGFloat(sampleCount)
                let candidate = CGPoint(
                    x: origin.x + cos(angle) * distance,
                    y: origin.y + sin(angle) * distance
                )
                guard boundary.contains(point: candidate, particleRadius: radius) else { continue }
                if contactPoint(around: candidate, radius: radius, mask: mask) == nil {
                    return candidate
                }
            }
        }

        return nil
    }

    private func boundary(for size: CGSize) -> DisplayBoundary {
        if let displayBoundary, displayBoundary.size == size {
            return displayBoundary
        }

        let newBoundary = DisplayBoundary(size: size)
        displayBoundary = newBoundary
        return newBoundary
    }

    private func dot(_ vector: CGVector, _ normal: CGVector) -> CGFloat {
        vector.dx * normal.dx + vector.dy * normal.dy
    }

    private func normalized(_ vector: CGVector) -> CGVector? {
        let length = sqrt(vector.dx * vector.dx + vector.dy * vector.dy)
        guard length > 0.0001 else { return nil }
        return CGVector(dx: vector.dx / length, dy: vector.dy / length)
    }

    private func clampVelocity(_ velocity: inout CGVector) {
        let speed = sqrt(velocity.dx * velocity.dx + velocity.dy * velocity.dy)
        guard speed > PerformanceConfig.maximumParticleSpeed else { return }
        let scale = PerformanceConfig.maximumParticleSpeed / speed
        velocity.dx *= scale
        velocity.dy *= scale
    }
}
