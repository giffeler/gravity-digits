import CoreGraphics
import Foundation

enum ParticleCountPreset {
    static let low = 250
    static let medium = 400
}

enum PerformanceConfig {
    static let defaultParticleCount = ParticleCountPreset.medium
    static let minimumParticleCount = ParticleCountPreset.low
    // There is no reason to retain inactive particles above the recovery target.
    static let maximumParticleCount = defaultParticleCount

    static let preferredFramesPerSecond = 30
    static let fixedTimeStep: TimeInterval = 1.0 / 30.0
    static let maxAccumulatedTime: TimeInterval = 0.12
    static let maximumSimulationStepsPerFrame = 1
    static let slowFrameInterval: TimeInterval = 1.0 / 24.0
    static let recoveryFrameInterval: TimeInterval = 1.0 / 28.0
    static let maximumFrameIntervalSample: TimeInterval = 0.2
    static let frameWorkBudget: TimeInterval = fixedTimeStep * 0.7
    static let particleRecoveryWorkBudget: TimeInterval = fixedTimeStep * 0.45
    static let adaptiveCheckInterval: TimeInterval = 2.0
    static let adaptiveReductionStep = 50
    static let adaptiveRecoveryStep = 10
    static let adaptiveRecoveryChecks = 3
    static let particleFadeDuration: TimeInterval = 0.35
    static let settledFramesPerSecond = 2
    // Ignore filtered accelerometer noise below roughly 0.02 g.
    static let settleGravityThresholdSquared: CGFloat = 64.0
    static let settleDelay: TimeInterval = 2.0
    static let settleKineticEnergyPerParticle: CGFloat = 12.5

    static let maskScale: CGFloat = 2.0
    static let gravityScale: CGFloat = 420.0
    static let maxGravityMagnitude: CGFloat = 1.35
    static let velocityDamping: CGFloat = 0.992
    // 1,200 pt/s * (1 / 30 s) / 48 substeps = 0.833 pt, below the 1 pt minimum radius.
    static let maximumParticleSpeed: CGFloat = 1_200.0
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
