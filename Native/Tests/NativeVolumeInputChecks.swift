import Foundation
import AppKit
import RealityKit
import simd

// Deterministic scene input with the shipped collision controller and real
// RealityKit physics. Actions are observed at the GameScene boundary; network
// acceptance and headset gaze delivery are deliberately separate checks.
struct RenderSnapshot {
    var center = SIMD3<Float>(3200, 10, 3200)
    var scale: Float = 0.08
    // Match a physical headset before any AR table has been placed. The
    // volume must obtain its footprint from the actual production policy.
    var boundary = TableGeometry.renderBoundary(boundary: [], size: [1.3, 0.9])
}
struct PickTarget { let kind: String; let actor: JSONObject; let meshes: [NativeMesh]; let transform: simd_float4x4 }
@MainActor final class GameSession { var connected = true }
@MainActor final class GameScene {
    let session = GameSession()
    var volumeInputEpoch = 1
    var volumeTerrainChunks: [(key: String, meshes: [NativeMesh])] = []
    var volumeTargets: [PickTarget] = []
    var selections: [(point: SIMD3<Float>, targetID: String?, terrain: Bool)] = []
    var status = ""
    func setVolumeInputStatus(_ value: String) { status = value }
    func selectVolumePoint(_ point: SIMD3<Float>, targetID: String?, terrain: Bool) {
        selections.append((point, targetID, terrain))
    }
}

@main struct NativeVolumeInputChecks {
    @MainActor static func main() {
        _ = NSApplication.shared
        let view = ARView(frame: CGRect(x: 0, y: 0, width: 640, height: 480))
        Task { @MainActor in
            do { try await run(view); exit(0) }
            catch { print("FAIL volume input: \(error)"); fflush(stdout); exit(1) }
        }
        RunLoop.main.run()
    }
    static func require(_ value: @autoclosure () -> Bool, _ message: String, line: UInt = #line) {
        guard value() else { print("FAIL volume input line \(line): \(message)"); fflush(stdout); exit(1) }
    }
    static func near(_ a: SIMD3<Float>, _ b: SIMD3<Float>, tolerance: Float = 0.002) -> Bool {
        simd_distance(a, b) < tolerance
    }
    static func quad(x0: Float, x1: Float, y: Float, z0: Float = 3198, z1: Float = 3202) -> NativeMesh {
        NativeMesh(vertices: [[x0,y,z0],[x0,y,z1],[x1,y,z1],[x1,y,z0]].map {
            NativeVertex(position: $0, color: [1,1,1,1])
        }, indices: [0,1,2,0,2,3])
    }
    static func actorMesh() -> NativeMesh {
        NativeMesh(vertices: [[-0.3,0,-0.3],[0.3,1.8,0.3]].map {
            NativeVertex(position: $0, color: [1,1,1,1])
        }, indices: [])
    }
    @MainActor static func pause() async throws { try await Task.sleep(for: .milliseconds(120)) }
    @MainActor static func descendants(_ entity: Entity) -> [Entity] {
        [entity] + entity.children.flatMap { descendants($0) }
    }
    @MainActor static func run(_ view: ARView) async throws {
        let unplacedBoundary: [SIMD2<Float>] = []
        let fallback = TableGeometry.renderBoundary(boundary: unplacedBoundary, size: [1.3, 0.9])
        let expected: [SIMD2<Float>] = [[-0.65,-0.45],[0.65,-0.45],[0.65,0.45],[-0.65,0.45]]
        require(fallback == expected, "Unplaced physical headset did not receive its visible window footprint")
        require(unplacedBoundary.isEmpty, "Window footprint mutated the unconfirmed physical table boundary")
        require(scInside(.zero, fallback) && !scInside([0.66,0], fallback) && !scInside([0,0.46], fallback), "Fallback polygon does not correctly admit the board center and reject outside points")
        let custom: [SIMD2<Float>] = [[-0.5,-0.3],[0.4,-0.35],[0.55,0.15],[0,0.4],[-0.45,0.2]]
        require(TableGeometry.renderBoundary(boundary: custom, size: [1.3,0.9]) == custom, "A valid custom physical footprint was replaced by the window fallback")
        let scene = GameScene()
        let input = VolumeInputController(scene: scene)
        let anchor = AnchorEntity(world: .zero), board = Entity()
        board.position = [0.15,-0.1,-0.4]
        board.orientation = simd_quatf(angle: 0.23, axis: [0,1,0])
        board.scale = SIMD3(repeating: 0.55)
        anchor.addChild(board); board.addChild(input.root); view.scene.anchors.append(anchor)
        var snapshot = RenderSnapshot()
        scene.volumeTerrainChunks = [
            (key: "0:3184:3184", meshes: [quad(x0: 3195, x1: 3199, y: 0)]),
            (key: "0:3200:3184", meshes: [quad(x0: 3201, x1: 3205, y: 15)]),
            (key: "0:3184:3200", meshes: [NativeMesh(vertices: [[3198,3203],[3198,3205],[3202,3205],[3202,3203]].map { point in
                let x = Float(point[0]), z = Float(point[1])
                return NativeVertex(position: [x, 10 + (x-3200)*0.75 + (z-3204)*0.5, z], color: [1,1,1,1])
            }, indices: [0,1,2,0,2,3])])
        ]
        // Feed actual ticks and await the asynchronous static-mesh cooks. Do not
        // mutate CollisionComponent filters to make the raycast pass.
        for _ in 0..<30 {
            input.update(snapshot: snapshot); try await pause()
            if descendants(input.root).filter({ $0.name == "Walkable terrain" }).count == 3 { break }
        }
        let surfaces = descendants(input.root).filter { $0.name == "Walkable terrain" }
        require(surfaces.count == 3, "Real terrain collision resources failed to cook: \(scene.status)")
        require(surfaces.allSatisfy { $0.components[InputTargetComponent.self] != nil }, "Terrain is not eligible for system spatial input")
        require(input.root.components[CollisionComponent.self] == nil, "An enclosing volume collision shape still intercepts terrain")

        func ray(_ point: SIMD3<Float>) -> [CollisionCastHit] {
            let from = board.convert(position: point + [0, 3, 0], to: nil)
            let to = board.convert(position: point - [0, 3, 0], to: nil)
            return view.scene.raycast(from: from, to: to, query: .all).sorted { $0.distance < $1.distance }
        }
        func boardPoint(_ hit: CollisionCastHit) -> SIMD3<Float> { board.convert(position: hit.position, from: nil) }
        let low = SIMD3<Float>(-0.24,-0.8,0), high = SIMD3<Float>(0.24,0.4,0)
        // A known local shape proves that the scene's physics query engine is
        // active before production terrain hits are assessed.
        let probe = ModelEntity(mesh: .generateBox(size: 0.1))
        probe.position = [0, 1, 0]; probe.generateCollisionShapes(recursive: false); board.addChild(probe)
        try await pause()
        require(ray([0,1,0]).contains { $0.entity === probe }, "RealityKit raycast engine did not initialize")
        probe.removeFromParent(); try await pause()
        guard let lowHit = ray(low).first, let highHit = ray(high).first else {
            throw NSError(domain: "VolumeInputChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: "Production terrain colliders were not hit by RealityKit scene raycasts"])
        }
        require(near(boardPoint(lowHit), low), "Lower terrain was intercepted at a volume boundary instead of its actual elevation: \(boardPoint(lowHit))")
        require(near(boardPoint(highHit), high), "High terrain hit does not match its visible elevation")
        require(ray([0,0,0]).isEmpty, "Empty space between surfaces is intercepted by an enclosing collision volume")
        let slopePoint = SIMD3<Float>(-0.064,-0.064,-0.288)
        guard let slope = ray(slopePoint).first else { fatalError("Sloped terrain collider missing") }
        require(near(boardPoint(slope), slopePoint), "Off-center sloped terrain hit is flattened, shifted, or scaled incorrectly: \(boardPoint(slope))")
        input.pick(entity: lowHit.entity, point: boardPoint(lowHit))
        input.pick(entity: highHit.entity, point: boardPoint(highHit))
        require(scene.selections.count == 2 && scene.selections.allSatisfy { $0.terrain && $0.targetID == nil }, "Terrain hits did not reach the walk action route")
        require(near(scene.selections[0].point, low) && near(scene.selections[1].point, high), "Tap coordinates were changed or flattened before GameScene")

        scene.volumeTargets = [PickTarget(kind: "npc", actor: ["id":41], meshes: [actorMesh()], transform: scTranslation([3200,10,3200]))]
        try await pause(); input.update(snapshot: snapshot); try await pause()
        guard let actorHit = ray([0,0,0]).first else { fatalError("Actor collider missing") }
        require(actorHit.entity.name == "Game action target", "NPC was not the nearest input target")
        require(near(boardPoint(actorHit), [0,0.144,0]), "NPC collider did not follow the rendered actor bounds")
        input.pick(entity: actorHit.entity, point: boardPoint(actorHit))
        require(scene.selections.last?.targetID == "npc:41" && scene.selections.last?.terrain == false, "Actor collider identity was lost")
        let actorEntity = actorHit.entity
        scene.volumeTargets = [PickTarget(kind: "npc", actor: ["id":41], meshes: [actorMesh()], transform: scTranslation([3203,15,3200]))]
        try await pause(); input.update(snapshot: snapshot); try await pause()
        require(ray([0,0,0]).isEmpty, "Moving NPC left a stale collider at its previous location")
        guard let moved = ray(high).first else { fatalError("Moving actor lost its collider") }
        require(moved.entity.id == actorEntity.id && near(boardPoint(moved), [0.24,0.544,0]), "NPC input target failed to follow movement or unnecessarily replaced its entity")
        input.pick(entity: moved.entity, point: boardPoint(moved))
        require(scene.selections.last?.targetID == "npc:41", "Moving target no longer dispatches its stable identity")

        // System resizing changes the parent transform, not the game point.
        board.scale = SIMD3(repeating: 0.31)
        board.position = [-0.25,0.2,-0.7]
        try await pause()
        guard let resized = ray(low).first else { fatalError("Resized board lost terrain collider") }
        require(near(boardPoint(resized), low), "System volume transform changed the terrain point")
        require(ray([-0.404,-0.8,0]).isEmpty, "Resized terrain collider extends beyond its visible footprint")
        guard let resizedSlope = ray(slopePoint).first else { fatalError("Resized sloped terrain missing") }
        require(near(boardPoint(resizedSlope), slopePoint), "Inherited resize does not scale sloped terrain vertices correctly")
        input.pick(entity: resized.entity, point: boardPoint(resized))
        require(near(scene.selections.last!.point, low), "Resized input was delivered in world coordinates instead of board coordinates")

        // Clockwise quarter turns use the same rotated parent for visible
        // scenery and production input entities. Exercise every turn together
        // with distinct system-window translations and scales. This non-square
        // footprint and two separated targets catch swapping/negating X and Z.
        let surfaceIDs = Set(surfaces.map(\.id))
        let actorTop = SIMD3<Float>(0.24, 0.544, 0)
        let expectedGameTerrain = SIMD3<Float>(3197, 0, 3200)
        let expectedGameActorTop = SIMD3<Float>(3203, 16.8, 3200)
        func expectedGamePosition(_ local: SIMD3<Float>) -> SIMD3<Float> {
            snapshot.center + SIMD3(local.x, local.y, -local.z) / snapshot.scale
        }
        for turn in 0..<4 {
            board.orientation = simd_quatf(angle: 0.23 - Float(turn) * .pi / 2, axis: [0, 1, 0])
            board.position = [-0.25 + Float(turn)*0.13, 0.2 + Float(turn)*0.07, -0.7 - Float(turn)*0.09]
            board.scale = SIMD3(repeating: 0.25 + Float(turn)*0.065)
            try await pause()
            guard let terrainHit = ray(low).first, let targetHit = ray(high).first else {
                fatalError("Quarter turn \(turn) lost the terrain or actor collision surface")
            }
            let terrainPoint = boardPoint(terrainHit), targetPoint = boardPoint(targetHit)
            require(terrainHit.entity.name == "Walkable terrain" && near(terrainPoint, low), "Quarter turn \(turn) moved the walk surface in board-local coordinates")
            require(targetHit.entity.id == actorEntity.id && near(targetPoint, actorTop), "Quarter turn \(turn) changed the actor identity or surface point")
            require(near(expectedGamePosition(terrainPoint), expectedGameTerrain), "Quarter turn \(turn) maps the terrain tap to a different game position")
            require(near(expectedGamePosition(targetPoint), expectedGameActorTop), "Quarter turn \(turn) maps the actor surface to a different game position")
            require(ray([0, 0, 0]).isEmpty, "Quarter turn \(turn) introduced a target in empty space")
            let previousSelections = scene.selections.count
            input.pick(entity: terrainHit.entity, point: terrainPoint)
            input.pick(entity: targetHit.entity, point: targetPoint)
            require(scene.selections.count == previousSelections + 2, "Quarter turn \(turn) did not dispatch both production controller selections")
            let walkSelection = scene.selections[previousSelections], actorSelection = scene.selections[previousSelections + 1]
            require(walkSelection.terrain && walkSelection.targetID == nil && near(walkSelection.point, low), "Quarter turn \(turn) changed the walk action boundary call")
            require(!actorSelection.terrain && actorSelection.targetID == "npc:41" && near(actorSelection.point, actorTop), "Quarter turn \(turn) changed the NPC action boundary call")
            require(surfaceIDs == Set(descendants(input.root).filter { $0.name == "Walkable terrain" }.map(\.id)), "Quarter turn \(turn) replaced immutable terrain collision entities")
        }

        // Re-centering follows live rendering without re-cooking terrain.
        snapshot.center = [3201,11,3199]; snapshot.scale = 0.1
        try await pause(); input.update(snapshot: snapshot); try await pause()
        guard let recentered = ray([-0.4,-1.1,-0.1]).first else { fatalError("Re-centered terrain missing") }
        require(near(boardPoint(recentered), [-0.4,-1.1,-0.1]), "Center or mirrored game Z transform drifted")
        require(surfaceIDs == Set(descendants(input.root).filter { $0.name == "Walkable terrain" }.map(\.id)), "Recenter re-cooked immutable terrain")

        scene.volumeTargets = []
        try await pause(); input.update(snapshot: snapshot); try await pause()
        let countBefore = scene.selections.count
        input.pick(entity: actorEntity, point: .zero)
        input.pick(entity: Entity(), point: .zero)
        require(scene.selections.count == countBefore, "Removed or foreign input entity dispatched a stale action")
        scene.session.connected = false
        try await pause(); input.update(snapshot: snapshot); try await pause()
        require(ray([-0.4,-1.1,-0.1]).isEmpty, "Disconnected map still accepts physics hits")
        input.stop(); try await pause()
        require(descendants(input.root).allSatisfy { $0.components[CollisionComponent.self] == nil }, "Stopped controller retained input colliders")
        require(ray([-0.4,-1.1,-0.1]).isEmpty, "Stopped volume still intercepts system queries")
        view.scene.anchors.removeAll()
        print("PASS production volume input: unplaced headset footprint fallback without changing physical placement, preserved custom polygon, real RealityKit surface raycasts at two elevations plus an off-center slope, empty-space rejection, terrain action routing, moving actor identity/bounds, transformed/resized parent and all four clockwise quarter turns with stable terrain points and actor identity, center/scale/Z parity without recook, stale entity rejection, disconnect, teardown")
        print("LIMIT: macOS collision resources and GameScene-boundary calls; physical gaze/pinch delivery and network action acceptance require visionOS checks. Exact board-polygon rejection belongs to production GameScene and is not simulated here.")
    }
}
