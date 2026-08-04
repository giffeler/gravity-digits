import SpriteKit
import SwiftUI
import WatchKit

struct ClockDisplayView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var motionManager = MotionManager()
    @State private var scene = ParticleScene()
    @State private var accessibilityTime = ""
    @State private var preferredFramesPerSecond = PerformanceConfig.preferredFramesPerSecond

    var body: some View {
        GeometryReader { proxy in
            let renderSize = fullScreenSize(fallback: proxy.size)

            SpriteView(
                scene: scene,
                isPaused: false,
                preferredFramesPerSecond: preferredFramesPerSecond
            )
                .frame(width: renderSize.width, height: renderSize.height)
                .ignoresSafeArea()
                .persistentSystemOverlays(.hidden)
                .background(Color.black)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Current time")
                .accessibilityValue(accessibilityTime)
                .onAppear {
                    scene.onTimeTextChanged = { accessibilityTime = $0 }
                    scene.onPreferredFramesPerSecondChanged = { preferredFramesPerSecond = $0 }
                    scene.configure(size: renderSize, motionManager: motionManager)
                    scene.setSimulationPaused(false)
                    motionManager.start()
                }
                .onDisappear {
                    scene.setSimulationPaused(true)
                    motionManager.stop()
                }
                .onChange(of: proxy.size) { _, newSize in
                    scene.configure(size: fullScreenSize(fallback: newSize), motionManager: motionManager)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        scene.configure(size: renderSize, motionManager: motionManager)
                        scene.setSimulationPaused(false)
                        motionManager.start()
                    default:
                        scene.setSimulationPaused(true)
                        motionManager.stop()
                    }
                }
        }
    }

    private func fullScreenSize(fallback: CGSize) -> CGSize {
        let screen = WKInterfaceDevice.current().screenBounds.size
        return CGSize(
            width: max(fallback.width, screen.width),
            height: max(fallback.height, screen.height)
        )
    }
}

#Preview {
    ClockDisplayView()
}
