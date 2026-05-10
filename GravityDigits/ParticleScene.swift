import CoreGraphics
import Foundation
import SpriteKit

final class ParticleScene: SKScene {
    private let particleSystem = ParticleSystem()
    private let particleLayer = SKNode()
    private let digitNode = SKSpriteNode()

    private weak var motionManager: MotionManager?
    private var particleNodes: [SKSpriteNode] = []
    private var particleTexture: SKTexture?
    private var digitMask: DigitMask?
    private var displayedMinuteKey = ""
    private var accumulator: TimeInterval = 0
    private var previousUpdateTime: TimeInterval?
    private var frameTimeAverage: TimeInterval = PerformanceConfig.fixedTimeStep
    private var lastAdaptiveCheck: TimeInterval = 0
    private var simulationPaused = false
    private var simulationTimer: Timer?

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
        ensureParticleNodes()
        renderParticles()
    }

    func setSimulationPaused(_ paused: Bool) {
        simulationPaused = paused
        isPaused = paused
        if paused {
            previousUpdateTime = nil
            accumulator = 0
            stopSimulationTimer()
        } else {
            startSimulationTimer()
        }
    }

    override func update(_ currentTime: TimeInterval) {
        guard simulationTimer == nil else { return }
        stepSimulation(currentTime: currentTime)
    }

    private func startSimulationTimer() {
        guard simulationTimer == nil else { return }
        previousUpdateTime = nil

        let timer = Timer(timeInterval: PerformanceConfig.fixedTimeStep, repeats: true) { [weak self] _ in
            self?.stepSimulation(currentTime: Date.timeIntervalSinceReferenceDate)
        }
        simulationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopSimulationTimer() {
        simulationTimer?.invalidate()
        simulationTimer = nil
    }

    private func stepSimulation(currentTime: TimeInterval) {
        guard !simulationPaused else { return }
        rebuildMaskIfNeeded(force: false)

        guard let previousUpdateTime else {
            self.previousUpdateTime = currentTime
            return
        }

        let frameDelta = min(currentTime - previousUpdateTime, PerformanceConfig.maxAccumulatedTime)
        self.previousUpdateTime = currentTime
        frameTimeAverage = frameTimeAverage * 0.92 + frameDelta * 0.08
        accumulator += frameDelta

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

        adaptParticleCountIfNeeded(currentTime: currentTime)
        renderParticles()
    }

    private func rebuildMaskIfNeeded(force: Bool) {
        let key = minuteKey()
        guard force || key != displayedMinuteKey else { return }
        displayedMinuteKey = key

        guard let mask = DigitMask.make(text: currentTimeText(), size: size) else { return }
        digitMask = mask
        digitNode.texture = mask.texture
        digitNode.size = size
        digitNode.position = .zero
    }

    private func ensureParticleNodes() {
        if particleTexture == nil {
            particleTexture = Self.makeParticleTexture()
        }
        guard let particleTexture else { return }

        while particleNodes.count < particleSystem.particles.count {
            let node = SKSpriteNode(texture: particleTexture)
            node.blendMode = .add
            node.zPosition = 1
            particleNodes.append(node)
            particleLayer.addChild(node)
        }
    }

    private func renderParticles() {
        ensureParticleNodes()
        let activeCount = min(particleSystem.activeParticleCount, particleSystem.particles.count, particleNodes.count)

        for index in 0..<particleNodes.count {
            let node = particleNodes[index]
            guard index < activeCount else {
                node.isHidden = true
                continue
            }

            let particle = particleSystem.particles[index]
            node.isHidden = false
            node.position = particle.position
            node.alpha = particle.alpha
            let diameter = particle.radius * 2.0
            node.size = CGSize(width: diameter, height: diameter)
        }
    }

    private func adaptParticleCountIfNeeded(currentTime: TimeInterval) {
        guard currentTime - lastAdaptiveCheck >= PerformanceConfig.adaptiveCheckInterval else { return }
        lastAdaptiveCheck = currentTime

        if frameTimeAverage > PerformanceConfig.frameBudget,
           particleSystem.activeParticleCount > PerformanceConfig.minimumParticleCount {
            particleSystem.setActiveParticleCount(particleSystem.activeParticleCount - PerformanceConfig.adaptiveStep)
        }
    }

    private func minuteKey() -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return "\(components.hour ?? 0):\(components.minute ?? 0)"
    }

    private func currentTimeText() -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        return String(format: "%02d:%02d", hour, minute)
    }

    private static func makeParticleTexture() -> SKTexture? {
        let dimension = 12
        let bytesPerPixel = 4
        let bytesPerRow = dimension * bytesPerPixel
        var rgba = [UInt8](repeating: 0, count: dimension * bytesPerRow)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: &rgba,
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
