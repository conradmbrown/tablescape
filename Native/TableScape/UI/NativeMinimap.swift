import Foundation
import simd

/// Screen fractions use top-left origin; game north is increasing Z.
enum NativeMinimapProjection {
    static let tilesAcross: Float = 48
    static func gamePosition(screen: SIMD2<Float>, center: SIMD2<Float>) -> SIMD2<Float>? {
        guard screen.x.isFinite, screen.y.isFinite, (0...1).contains(screen.x), (0...1).contains(screen.y) else { return nil }
        return center + SIMD2(screen.x - 0.5, 0.5 - screen.y) * tilesAcross
    }
    static func screenPosition(game: SIMD2<Float>, center: SIMD2<Float>) -> SIMD2<Float> {
        let delta = (game - center) / tilesAcross
        return SIMD2(0.5 + delta.x, 0.5 - delta.y)
    }
}

#if MINIMAP_GEOMETRY_CHECKS
@main enum NativeMinimapChecks {
    static func main() {
        let center = SIMD2<Float>(3222.5, 3218.5)
        precondition(NativeMinimapProjection.gamePosition(screen: SIMD2(0.5, 0.5), center: center) == center)
        precondition(NativeMinimapProjection.gamePosition(screen: SIMD2(0.5, 0), center: center) == center + SIMD2(0, 24))
        precondition(NativeMinimapProjection.gamePosition(screen: SIMD2(1, 0.5), center: center) == center + SIMD2(24, 0))
        precondition(NativeMinimapProjection.gamePosition(screen: SIMD2(0.5, 1), center: center) == center - SIMD2(0, 24))
        precondition(NativeMinimapProjection.gamePosition(screen: SIMD2(0, 0.5), center: center) == center - SIMD2(24, 0))
        precondition(NativeMinimapProjection.gamePosition(screen: SIMD2(-0.01, 0.5), center: center) == nil)
        precondition(NativeMinimapProjection.gamePosition(screen: SIMD2(Float.nan, 0), center: center) == nil)
        for x in 0...10 { for y in 0...10 {
            let screen = SIMD2(Float(x) / 10, Float(y) / 10)
            let game = NativeMinimapProjection.gamePosition(screen: screen, center: center)!
            precondition(simd_distance(screen, NativeMinimapProjection.screenPosition(game: game, center: center)) < 0.0001)
        } }
        print("PASS: minimap north/east/south/west orientation, bounds, nonfinite rejection, and 121 inverse mappings")
    }
}
#else
import SwiftUI
import MetalKit

/// Uses the same scene snapshot and source meshes as tabletop rendering.
struct NativeMinimap: View {
    @ObservedObject var scene: GameScene
    @ObservedObject private var session: GameSession
    init(scene: GameScene) { self.scene = scene; self.session = scene.session }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                MinimapMetalView(scene: scene)
                TimelineView(.animation(minimumInterval: 0.1, paused: !session.connected)) { _ in
                    Canvas { context, size in
                        let snapshot = scene.exchange.read(), center = SIMD2(snapshot.center.x, snapshot.center.z)
                        func dot(_ actor: JSONObject, color: Color, radius: CGFloat) {
                            let position = SIMD2(Float(actor.double("x")) + 0.5, Float(actor.double("z")) + 0.5)
                            let point = NativeMinimapProjection.screenPosition(game: position, center: center)
                            guard (0...1).contains(point.x), (0...1).contains(point.y) else { return }
                            let rectangle = CGRect(x: CGFloat(point.x) * size.width - radius, y: CGFloat(point.y) * size.height - radius, width: radius * 2, height: radius * 2)
                            context.fill(Path(ellipseIn: rectangle), with: .color(color))
                        }
                        for actor in session.state.objects("npcs") { dot(actor, color: .yellow, radius: 2) }
                        for actor in session.state.objects("players") { dot(actor, color: .cyan, radius: 2) }
                        if !session.player.isEmpty { dot(session.player, color: .white, radius: 3) }
                    }
                }.allowsHitTesting(false)
                VStack { Text("N").font(.caption.bold()).padding(3).background(.black.opacity(0.5), in: Capsule()); Spacer() }
                    .padding(3).allowsHitTesting(false)
            }
            .frame(width: 160, height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.25)))
            .accessibilityLabel("North-up world map. Tap a location to walk there.")
            Button("Center on character", systemImage: "scope") {
                // The game center always follows the player; reset presentation controls only.
                scene.orbit = 0; scene.tilt = 0.8; scene.tilesAcross = 34; scene.resetTableRotation()
            }.font(.caption).buttonStyle(.borderless)
                .accessibilityIdentifier("world.recenter")
        }
    }
}

@MainActor private final class MinimapDelegate: NSObject, MTKViewDelegate {
    let scene: GameScene
    var renderer: MetalSceneRenderer?
    init(scene: GameScene) { self.scene = scene; super.init() }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        guard let renderer, let descriptor = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let buffer = renderer.commandBuffer() else { return }
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.03, green: 0.04, blue: 0.025, alpha: 1)
        descriptor.depthAttachment.clearDepth = 0
        var snapshot = scene.exchange.read()
        snapshot.nodes.removeAll { $0.billboard }
        snapshot.placementNodes = []
        snapshot.boundary = [SIMD2(-0.5, -0.5), SIMD2(0.5, -0.5), SIMD2(0.5, 0.5), SIMD2(-0.5, 0.5)]
        snapshot.scale = 1 / NativeMinimapProjection.tilesAcross
        snapshot.tableQuarterTurns = 0 // Keep map pixels aligned with north-up markers and taps.
        // Looking straight down with camera-up toward game north (board -Z).
        let camera = simd_float4x4(columns: (SIMD4(1, 0, 0, 0), SIMD4(0, 0, -1, 0), SIMD4(0, 1, 0, 0), SIMD4(0, 2, 0, 1)))
        let near: Float = 0.01, far: Float = 5
        let projection = simd_float4x4(columns: (SIMD4(2, 0, 0, 0), SIMD4(0, 2, 0, 0), SIMD4(0, 0, 1 / (far - near), 0), SIMD4(0, 0, far / (far - near), 1)))
        renderer.prepare(snapshot)
        if let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor) {
            renderer.encode(encoder, snapshot: snapshot, viewProjection: projection * camera.inverse, board: matrix_identity_float4x4, cameraWorld: camera, preview: true)
            encoder.endEncoding()
        }
        buffer.present(drawable); buffer.commit()
    }
    @objc func tap(_ gesture: UITapGestureRecognizer) {
        guard scene.session.connected, let view = gesture.view, view.bounds.width > 0, view.bounds.height > 0 else { return }
        let point = gesture.location(in: view), snapshot = scene.exchange.read()
        let screen = SIMD2(Float(point.x / view.bounds.width), Float(point.y / view.bounds.height))
        guard let game = NativeMinimapProjection.gamePosition(screen: screen, center: SIMD2(snapshot.center.x, snapshot.center.z)) else { return }
        scene.session.move(x: Int(floor(game.x)), z: Int(floor(game.y)))
    }
}

private struct MinimapMetalView: UIViewRepresentable {
    let scene: GameScene
    func makeCoordinator() -> MinimapDelegate { MinimapDelegate(scene: scene) }
    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.colorPixelFormat = .bgra8Unorm_srgb; view.depthStencilPixelFormat = .depth32Float
        view.preferredFramesPerSecond = 10
        view.accessibilityIdentifier = "world.minimap"
        if let device = view.device {
            do { context.coordinator.renderer = try MetalSceneRenderer(device: device, color: view.colorPixelFormat) }
            catch { scene.status = "Minimap: \(error.localizedDescription)" }
        }
        view.delegate = context.coordinator
        view.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(MinimapDelegate.tap(_:))))
        return view
    }
    func updateUIView(_ uiView: MTKView, context: Context) {}
}
#endif
