import SwiftUI
import RealityKit
import simd

/// System window chrome moves and resizes the table. Native spatial taps land
/// on terrain and actor collision surfaces, without requiring a private gaze ray.
struct VolumetricTableView: View {
    @ObservedObject var model: TableScapeModel
    @ObservedObject var scene: GameScene
    @StateObject private var renderer: VolumetricTableRenderer

    init(model: TableScapeModel) {
        self.model = model
        self.scene = model.scene
        _renderer = StateObject(wrappedValue: VolumetricTableRenderer(scene: model.scene))
    }
    var body: some View {
        GeometryReader3D { geometry in
            RealityView { content in
                content.add(renderer.root)
                // Fit in the parent entity's coordinates; the window scene and
                // RealityView root have different depth origins.
                renderer.resize(to: content.convert(geometry.frame(in: .global), from: .global, to: renderer.root))
            } update: { content in
                renderer.resize(to: content.convert(geometry.frame(in: .global), from: .global, to: renderer.root))
            }
            .gesture(SpatialTapGesture().targetedToAnyEntity()
                .onEnded { value in
                    let point = value.convert(value.location3D, from: .local, to: renderer.boardRoot)
                    renderer.tap(entity: value.entity, point: point)
                })
            .ornament(attachmentAnchor: .scene(.bottomFront), contentAlignment: .bottom) {
                TableGameMenu(model: model)
                    .frame(width: 640)
                    .glassBackgroundEffect()
            }
        }
        .frame(minWidth: 500, maxWidth: 1800, minHeight: 350, maxHeight: 1400)
        .frame(minDepth: 350, maxDepth: 1400)
        .volumeBaseplateVisibility(.visible)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("world.volume")
        .accessibilityLabel("Three-dimensional TableScape table. Look and pinch for actions or to walk.")
        .accessibilityValue(renderer.status + " · " + scene.volumeInputStatus + " · taps=\(scene.volumeTapCount) · rotation=\(scene.exchange.read().tableQuarterTurns * 90)° · tiles=\(Int(scene.tilesAcross))")
        .task { await renderer.start() }
        .onDisappear { renderer.stop() }
    }
}
