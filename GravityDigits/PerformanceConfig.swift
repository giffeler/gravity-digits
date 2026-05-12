import CoreGraphics
import Foundation

enum ParticleCountPreset {
    static let low = 400
    static let medium = 800
    static let high = 1_200
    static let extreme = 2_000
}

enum PerformanceConfig {
    static let defaultParticleCount = ParticleCountPreset.medium
    static let minimumParticleCount = ParticleCountPreset.low
    static let maximumParticleCount = ParticleCountPreset.extreme

    static let preferredFramesPerSecond = 30
    static let fixedTimeStep: TimeInterval = 1.0 / 30.0
    static let maxAccumulatedTime: TimeInterval = 0.12
    static let frameBudget: TimeInterval = 1.0 / 22.0
    static let adaptiveCheckInterval: TimeInterval = 2.0
    static let adaptiveStep = 100

    static let maskScale: CGFloat = 2.0
    static let gravityScale: CGFloat = 420.0
    static let maxGravityMagnitude: CGFloat = 1.35
    static let velocityDamping: CGFloat = 0.992
    static let edgeRestitution: CGFloat = 0.28
    static let edgeTangentialDamping: CGFloat = 0.88
    static let glyphRestitution: CGFloat = 0.12
    static let glyphTangentialDamping: CGFloat = 0.82
    static let displayCornerRadiusRatio: CGFloat = 0.235
    static let displayEdgeInset: CGFloat = 2.0
    static let minimumParticleStepDistance: CGFloat = 0.9
    static let maximumParticleSubsteps = 48
    static let minimumGlyphSweepStepDistance: CGFloat = 0.5
    static let maximumGlyphSweepSteps = 64

    static let minimumParticleRadius: CGFloat = 1.0
    static let maximumParticleRadius: CGFloat = 1.75
}
