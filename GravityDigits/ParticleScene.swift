import CoreGraphics
import Foundation
import SpriteKit

final class ParticleScene: SKScene {
    private struct MinuteSnapshot {
        let key: String
        let text: String
        let start: Date
        let nextMinute: Date
    }

    var onTimeTextChanged: ((String) -> Void)?
    var onPreferredFramesPerSecondChanged: ((Int) -> Void)?

    private let particleSystem = ParticleSystem()
    private let particleLayer = SKNode()
    private let digitNode = SKSpriteNode()

    private weak var motionManager: MotionManager?
    private var particleNodes: [SKSpriteNode] = []
    private var renderedActiveParticleCount = -1
    private var particleTexture: SKTexture?
    private var digitMask: DigitMask?
    private var particleBounds: CGSize?
    private var displayedMinuteKey = ""
    private var pendingMaskKey: String?
    private var pendingMaskSize: CGSize?
    private var maskBuildGeneration = 0
    private var installedMaskSinceLastUpdate = false
    private var cachedMinute: MinuteSnapshot?
    private var accumulator: TimeInterval = 0
    private var previousUpdateTime: TimeInterval?
    private var frameWorkAverage: TimeInterval = 0
    private var frameIntervalAverage: TimeInterval = PerformanceConfig.fixedTimeStep
    private var lastAdaptiveCheck: TimeInterval = 0
    private var consecutiveRecoveryChecks = 0
    private var simulationPaused = false
    private var lastGravity: CGVector?
    private var gravityStableSince: TimeInterval?
    private var settledGravity: CGVector?
    private var isSettled = false
    private(set) var completedSimulationStepCount = 0

    override init() {
        super.init(size: .zero)
        scaleMode = .resizeFill
        anchorPoint = .zero
        backgroundColor = .black
        addChild(particleLayer)
        digitNode.anchorPoint = .zero
        digitNode.zPosition = 10
        addChild(digitNode)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(size newSize: CGSize, motionManager: MotionManager) {
        self.motionManager = motionManager
        guard newSize.width > 1, newSize.height > 1 else { return }

        let roundedSize = CGSize(width: newSize.width.rounded(.down), height: newSize.height.rounded(.down))
        if size != roundedSize {
            size = roundedSize
            digitMask = nil
            displayedMinuteKey = ""
        }

        rebuildMaskIfNeeded(force: digitMask == nil)
        renderParticles()
    }

    func setSimulationPaused(_ paused: Bool) {
        simulationPaused = paused
        isPaused = paused
        if paused {
            previousUpdateTime = nil
            accumulator = 0
            lastGravity = nil
            gravityStableSince = nil
            setSettled(false)
        }
    }

    override func update(_ currentTime: TimeInterval) {
        stepSimulation(currentTime: currentTime)
    }

    private func stepSimulation(currentTime: TimeInterval) {
        guard !simulationPaused else { return }
        let rebuiltMask = installedMaskSinceLastUpdate
        installedMaskSinceLastUpdate = false
        rebuildMaskIfNeeded(force: false)

        guard let previousUpdateTime else {
            self.previousUpdateTime = currentTime
            return
        }

        let unboundedFrameDelta = max(0, currentTime - previousUpdateTime)
        let frameDelta = min(unboundedFrameDelta, PerformanceConfig.maxAccumulatedTime)
        self.previousUpdateTime = currentTime
        accumulator += frameDelta

        let workStart = ProcessInfo.processInfo.systemUptime
        let gravity = motionManager?.gravityVector ?? CGVector(dx: 0, dy: -PerformanceConfig.gravityScale)
        let wasSettled = isSettled
        updateSettleState(gravity: gravity, currentTime: currentTime)
        if isSettled {
            accumulator = 0
            return
        }

        var simulationStepCount = 0
        while accumulator >= PerformanceConfig.fixedTimeStep,
              simulationStepCount < PerformanceConfig.maximumSimulationStepsPerFrame {
            particleSystem.update(
                bounds: size,
                gravity: gravity,
                mask: digitMask,
                timeStep: CGFloat(PerformanceConfig.fixedTimeStep)
            )
            completedSimulationStepCount += 1
            simulationStepCount += 1
            accumulator -= PerformanceConfig.fixedTimeStep
        }
        if accumulator >= PerformanceConfig.fixedTimeStep {
            accumulator.formTruncatingRemainder(dividingBy: PerformanceConfig.fixedTimeStep)
        }

        if simulationStepCount > 0 {
            renderParticles()
        }
        if simulationStepCount > 0,
           !particleSystem.particles.isEmpty,
           let gravityStableSince,
           currentTime - gravityStableSince >= PerformanceConfig.settleDelay,
           particleSystem.totalKineticEnergy < PerformanceConfig.settleKineticEnergyPerParticle
            * CGFloat(particleSystem.activeParticleCount) {
            setSettled(true, gravity: gravity)
        }
        let workDuration = ProcessInfo.processInfo.systemUptime - workStart
        if wasSettled {
            resetPerformanceSamples()
        } else if !rebuiltMask {
            frameWorkAverage = frameWorkAverage * 0.92 + workDuration * 0.08
            if unboundedFrameDelta > 0,
               unboundedFrameDelta <= PerformanceConfig.maximumFrameIntervalSample {
                frameIntervalAverage = frameIntervalAverage * 0.92 + unboundedFrameDelta * 0.08
            }
        }
        adaptParticleCountIfNeeded(currentTime: currentTime)
    }

    private func rebuildMaskIfNeeded(force: Bool) {
        guard size.width > 1, size.height > 1 else { return }
        let minute = minuteSnapshot()
        let key = minute.key
        guard force || key != displayedMinuteKey else { return }
        guard pendingMaskKey != key || pendingMaskSize != size else { return }

        let timeText = minute.text
        let buildSize = size
        maskBuildGeneration += 1
        let generation = maskBuildGeneration
        pendingMaskKey = key
        pendingMaskSize = buildSize

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let mask = DigitMask.make(text: timeText, size: buildSize)
            DispatchQueue.main.async {
                guard let self, self.maskBuildGeneration == generation else { return }
                self.pendingMaskKey = nil
                self.pendingMaskSize = nil
                guard self.size == buildSize, self.minuteSnapshot().key == key, let mask else { return }

                self.digitMask = mask
                self.displayedMinuteKey = key
                if self.particleBounds != buildSize {
                    self.particleSystem.reset(in: buildSize, avoiding: mask)
                    self.particleBounds = buildSize
                    self.gravityStableSince = nil
                    self.setSettled(false)
                    self.bindParticleNodes()
                }
                let relocatedParticleIndices = self.particleSystem.ejectParticles(
                    overlapping: mask,
                    in: buildSize
                )
                if !relocatedParticleIndices.isEmpty {
                    self.accumulator = 0
                    self.lastGravity = nil
                    self.gravityStableSince = nil
                    self.setSettled(false)
                }
                self.digitNode.texture = mask.texture
                self.digitNode.size = buildSize
                self.digitNode.position = .zero
                self.installedMaskSinceLastUpdate = true
                self.renderParticles()
                self.fadeInParticles(at: relocatedParticleIndices)
                self.onTimeTextChanged?(timeText)
            }
        }
    }

    private func ensureParticleNodes() {
        if particleTexture == nil {
            particleTexture = Self.makeParticleTexture()
        }
        guard let particleTexture else { return }

        while particleNodes.count < particleSystem.particles.count {
            let node = SKSpriteNode(texture: particleTexture)
            let particle = particleSystem.particles[particleNodes.count]
            node.blendMode = .add
            node.zPosition = 1
            node.alpha = particle.alpha
            let diameter = particle.radius * 2.0
            node.size = CGSize(width: diameter, height: diameter)
            particleNodes.append(node)
            particleLayer.addChild(node)
        }
    }

    private func bindParticleNodes() {
        ensureParticleNodes()
        for index in 0..<min(particleNodes.count, particleSystem.particles.count) {
            let particle = particleSystem.particles[index]
            let node = particleNodes[index]
            node.removeAllActions()
            node.alpha = particle.alpha
            node.isHidden = index >= particleSystem.activeParticleCount
            let diameter = particle.radius * 2.0
            node.size = CGSize(width: diameter, height: diameter)
        }
        renderedActiveParticleCount = particleSystem.activeParticleCount
    }

    private func renderParticles() {
        ensureParticleNodes()
        let activeCount = min(particleSystem.activeParticleCount, particleSystem.particles.count, particleNodes.count)

        if activeCount != renderedActiveParticleCount {
            for index in 0..<particleNodes.count {
                particleNodes[index].isHidden = index >= activeCount
            }
            renderedActiveParticleCount = activeCount
        }

        for index in 0..<activeCount {
            particleNodes[index].position = particleSystem.particles[index].position
        }
    }

    private func adaptParticleCountIfNeeded(currentTime: TimeInterval) {
        guard currentTime - lastAdaptiveCheck >= PerformanceConfig.adaptiveCheckInterval else { return }
        lastAdaptiveCheck = currentTime

        let isOverBudget = frameWorkAverage > PerformanceConfig.frameWorkBudget
            || frameIntervalAverage > PerformanceConfig.slowFrameInterval
        let hasRecoveryHeadroom = frameWorkAverage < PerformanceConfig.particleRecoveryWorkBudget
            && frameIntervalAverage < PerformanceConfig.recoveryFrameInterval

        if isOverBudget,
           particleSystem.activeParticleCount > PerformanceConfig.minimumParticleCount {
            consecutiveRecoveryChecks = 0
            fadeOutParticles(
                downTo: particleSystem.activeParticleCount - PerformanceConfig.adaptiveReductionStep
            )
        } else if hasRecoveryHeadroom,
                  particleSystem.activeParticleCount < PerformanceConfig.defaultParticleCount {
            consecutiveRecoveryChecks += 1
            guard consecutiveRecoveryChecks >= PerformanceConfig.adaptiveRecoveryChecks else { return }
            consecutiveRecoveryChecks = 0
            activateParticles(
                upTo: particleSystem.activeParticleCount + PerformanceConfig.adaptiveRecoveryStep
            )
        } else {
            consecutiveRecoveryChecks = 0
        }
    }

    private func fadeOutParticles(downTo requestedCount: Int) {
        let oldCount = min(particleSystem.activeParticleCount, particleNodes.count)
        particleSystem.setActiveParticleCount(requestedCount)
        let newCount = min(particleSystem.activeParticleCount, particleNodes.count)
        guard newCount < oldCount else { return }

        for index in newCount..<oldCount {
            let node = particleNodes[index]
            node.removeAllActions()
            node.run(.sequence([
                .fadeOut(withDuration: PerformanceConfig.particleFadeDuration),
                .hide()
            ]))
        }
        renderedActiveParticleCount = newCount
    }

    private func activateParticles(upTo requestedCount: Int) {
        let activatedRange = particleSystem.activateParticles(
            upTo: requestedCount,
            in: size,
            avoiding: digitMask
        )
        guard !activatedRange.isEmpty else { return }

        for index in activatedRange where index < particleNodes.count {
            let particle = particleSystem.particles[index]
            let node = particleNodes[index]
            node.removeAllActions()
            node.position = particle.position
            node.size = CGSize(width: particle.radius * 2.0, height: particle.radius * 2.0)
            node.alpha = 0
            node.isHidden = false
            node.run(.fadeAlpha(to: particle.alpha, duration: PerformanceConfig.particleFadeDuration))
        }
        renderedActiveParticleCount = particleSystem.activeParticleCount
    }

    private func fadeInParticles(at indices: [Int]) {
        for index in indices where index < particleSystem.activeParticleCount && index < particleNodes.count {
            let particle = particleSystem.particles[index]
            let node = particleNodes[index]
            node.removeAllActions()
            node.alpha = 0
            node.isHidden = false
            node.run(.fadeAlpha(to: particle.alpha, duration: PerformanceConfig.particleFadeDuration))
        }
    }

    private func resetPerformanceSamples() {
        frameWorkAverage = 0
        frameIntervalAverage = PerformanceConfig.fixedTimeStep
        consecutiveRecoveryChecks = 0
        lastAdaptiveCheck = 0
    }

    private func updateSettleState(gravity: CGVector, currentTime: TimeInterval) {
        if let settledGravity {
            let dx = gravity.dx - settledGravity.dx
            let dy = gravity.dy - settledGravity.dy
            guard dx * dx + dy * dy > PerformanceConfig.settleGravityThresholdSquared else { return }

            lastGravity = gravity
            gravityStableSince = currentTime
            accumulator = 0
            setSettled(false)
            return
        }

        defer { lastGravity = gravity }
        guard let lastGravity else {
            gravityStableSince = currentTime
            return
        }

        let dx = gravity.dx - lastGravity.dx
        let dy = gravity.dy - lastGravity.dy
        guard dx * dx + dy * dy > PerformanceConfig.settleGravityThresholdSquared else { return }

        gravityStableSince = currentTime
        accumulator = 0
        setSettled(false)
    }

    private func setSettled(_ settled: Bool, gravity: CGVector? = nil) {
        guard isSettled != settled else { return }
        isSettled = settled
        settledGravity = settled ? gravity : nil
        onPreferredFramesPerSecondChanged?(
            settled ? PerformanceConfig.settledFramesPerSecond : PerformanceConfig.preferredFramesPerSecond
        )
    }

    private func minuteSnapshot(at date: Date = Date()) -> MinuteSnapshot {
        if let cachedMinute, date >= cachedMinute.start, date < cachedMinute.nextMinute {
            return cachedMinute
        }

        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        let interval = calendar.dateInterval(of: .minute, for: date)
        let start = interval?.start ?? date
        let nextMinute = interval?.end ?? date.addingTimeInterval(60)
        let snapshot = MinuteSnapshot(
            key: "\(hour):\(minute)",
            text: String(format: "%02d:%02d", hour, minute),
            start: start,
            nextMinute: nextMinute
        )
        cachedMinute = snapshot
        return snapshot
    }

    private static func makeParticleTexture() -> SKTexture? {
        let dimension = 12
        let bytesPerPixel = 4
        let bytesPerRow = dimension * bytesPerPixel
        let rgba = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: dimension * bytesPerRow)
        rgba.initialize(repeating: 0)
        defer { rgba.deallocate() }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: rgba.baseAddress,
                width: dimension,
                height: dimension,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }

        context.clear(CGRect(x: 0, y: 0, width: dimension, height: dimension))
        context.setFillColor(CGColor(red: 0.72, green: 0.92, blue: 1.0, alpha: 1.0))
        context.fillEllipse(in: CGRect(x: 1, y: 1, width: dimension - 2, height: dimension - 2))

        guard let image = context.makeImage() else { return nil }
        let texture = SKTexture(cgImage: image)
        texture.filteringMode = .linear
        return texture
    }
}
