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

    private let particleSystem = ParticleSystem()
    private let particleLayer = SKNode()
    private let digitNode = SKSpriteNode()

    private weak var motionManager: MotionManager?
    private var particleNodes: [SKSpriteNode] = []
    private var renderedActiveParticleCount = -1
    private var particleTexture: SKTexture?
    private var digitMask: DigitMask?
    private var displayedMinuteKey = ""
    private var pendingMaskKey: String?
    private var pendingMaskSize: CGSize?
    private var maskBuildGeneration = 0
    private var installedMaskSinceLastUpdate = false
    private var cachedMinute: MinuteSnapshot?
    private var accumulator: TimeInterval = 0
    private var previousUpdateTime: TimeInterval?
    private var frameTimeAverage: TimeInterval = PerformanceConfig.fixedTimeStep
    private var lastAdaptiveCheck: TimeInterval = 0
    private var simulationPaused = false

    override init() {
        super.init(size: CGSize(width: 184, height: 224))
        scaleMode = .resizeFill
        anchorPoint = .zero
        backgroundColor = .black
        addChild(particleLayer)
        digitNode.anchorPoint = .zero
        digitNode.zPosition = 10
        addChild(digitNode)
        particleSystem.reset(in: size, avoiding: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(size newSize: CGSize, motionManager: MotionManager) {
        self.motionManager = motionManager
        guard newSize.width > 1, newSize.height > 1 else { return }

        let roundedSize = CGSize(width: newSize.width.rounded(.down), height: newSize.height.rounded(.down))
        let needsParticleReset = size != roundedSize
        let needsInitialMask = digitMask == nil
        if size != roundedSize {
            size = roundedSize
            digitMask = nil
            displayedMinuteKey = ""
            particleSystem.reset(in: roundedSize, avoiding: nil)
        }

        rebuildMaskIfNeeded(force: digitMask == nil)
        if needsParticleReset || needsInitialMask, let digitMask {
            particleSystem.reset(in: roundedSize, avoiding: digitMask)
        }
        bindParticleNodes()
        renderParticles()
    }

    func setSimulationPaused(_ paused: Bool) {
        simulationPaused = paused
        isPaused = paused
        if paused {
            previousUpdateTime = nil
            accumulator = 0
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

        let frameDelta = min(currentTime - previousUpdateTime, PerformanceConfig.maxAccumulatedTime)
        self.previousUpdateTime = currentTime
        accumulator += frameDelta

        let workStart = ProcessInfo.processInfo.systemUptime
        let gravity = motionManager?.gravityVector ?? CGVector(dx: 0, dy: -PerformanceConfig.gravityScale)
        while accumulator >= PerformanceConfig.fixedTimeStep {
            particleSystem.update(
                bounds: size,
                gravity: gravity,
                mask: digitMask,
                timeStep: CGFloat(PerformanceConfig.fixedTimeStep)
            )
            accumulator -= PerformanceConfig.fixedTimeStep
        }

        renderParticles()
        let workDuration = ProcessInfo.processInfo.systemUptime - workStart
        if !rebuiltMask {
            frameTimeAverage = frameTimeAverage * 0.92 + workDuration * 0.08
        }
        adaptParticleCountIfNeeded(currentTime: currentTime)
    }

    private func rebuildMaskIfNeeded(force: Bool) {
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
                self.particleSystem.ejectParticles(overlapping: mask, in: buildSize)
                self.digitNode.texture = mask.texture
                self.digitNode.size = buildSize
                self.digitNode.position = .zero
                self.installedMaskSinceLastUpdate = true
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
            node.alpha = particle.alpha
            let diameter = particle.radius * 2.0
            node.size = CGSize(width: diameter, height: diameter)
        }
        renderedActiveParticleCount = -1
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

        if frameTimeAverage > PerformanceConfig.frameBudget,
           particleSystem.activeParticleCount > PerformanceConfig.minimumParticleCount {
            particleSystem.setActiveParticleCount(particleSystem.activeParticleCount - PerformanceConfig.adaptiveStep)
        } else if frameTimeAverage < PerformanceConfig.particleRecoveryBudget,
                  particleSystem.activeParticleCount < PerformanceConfig.defaultParticleCount {
            particleSystem.setActiveParticleCount(particleSystem.activeParticleCount + PerformanceConfig.adaptiveStep)
        }
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
