import Foundation
import AppKit
import RealityKit
import Combine
import simd

private func precondition(_ value: @autoclosure () -> Bool, _ message: @autoclosure () -> String = "", line: UInt = #line) {
    guard value() else { print("FAIL volume renderer line \(line): \(message())"); fflush(stdout); exit(1) }
}

// The exact production renderer is compiled against a small deterministic scene
// feed. No network/session implementation is replaced in the shipped app.
final class RenderGeometry { let id=UUID(); let mesh:NativeMesh; init(_ mesh:NativeMesh){self.mesh=mesh} }
struct RenderNode { let geometry:RenderGeometry; var transform=matrix_identity_float4x4; var tint=SIMD4<Float>(repeating:1); var billboard=false }
struct RenderSnapshot {
    var nodes:[RenderNode]=[];var textures:[Int:Data]=[:];var center=SIMD3<Float>(3200,10,3200);var scale:Float=0.08
    var boundary:[SIMD2<Float>]=[[-0.65,-0.45],[0.65,-0.45],[0.65,0.45],[-0.65,0.45]]
    var visible=false
    var tableQuarterTurns=0
}
@MainActor final class SceneExchange {var value=RenderSnapshot();func read()->RenderSnapshot{value}}
@MainActor final class GameSession {var sessionEpoch=1}
@MainActor final class GameScene:ObservableObject {
    let session=GameSession(),exchange=SceneExchange()
}
// Input geometry is exercised separately by NativeVolumeInputChecks using the
// production controller. Keep this render-resource suite focused on its scene feed.
@MainActor final class VolumeInputController {
    let root = Entity()
    init(scene: GameScene) {}
    func update(snapshot: RenderSnapshot) {}
    func stop() {}
    func pick(entity: Entity, point: SIMD3<Float>) {}
}
@main struct NativeVolumeRendererChecks {
    @MainActor static func main() {
        _=NSApplication.shared;let engine=ARView(frame:.zero)
        Task { @MainActor in
            do {try await run();_=engine;exit(0)} catch {print("FAIL volume renderer: \(error)");exit(1)}
        }
        RunLoop.main.run()
    }
    // RealityKit may vend different Swift wrappers for the same underlying
    // resource. Check shared storage instead of comparing wrapper addresses.
    // No await occurs while the fixture's harmless UV sentinel is installed.
    @MainActor static func sharesVertexStorage(_ retained: LowLevelMesh, _ current: LowLevelMesh) -> Bool {
        var original = SIMD2<Float>.zero
        retained.withUnsafeBytes(bufferIndex: 0) { original = $0.bindMemory(to: NativeVertex.self)[0].uv }
        let sentinel = original + SIMD2<Float>(1003.25,-907.5)
        retained.withUnsafeMutableBytes(bufferIndex: 0) { $0.bindMemory(to: NativeVertex.self)[0].uv = sentinel }
        var observed = SIMD2<Float>.zero
        current.withUnsafeBytes(bufferIndex: 0) { observed = $0.bindMemory(to: NativeVertex.self)[0].uv }
        retained.withUnsafeMutableBytes(bufferIndex: 0) { $0.bindMemory(to: NativeVertex.self)[0].uv = original }
        return observed == sentinel
    }
    @MainActor static func verifyPlayerCenter() async throws {
        let scene = GameScene()
        let actualRenderer = VolumetricTableRenderer(scene: scene)
        let selfGeometry = RenderGeometry(NativeMesh(vertices: [
            NativeVertex(position: .zero, color: [1,1,1,1]),
            NativeVertex(position: [0.2,0,0], color: [1,1,1,1]),
            NativeVertex(position: [0,1,0.2], color: [1,1,1,1])
        ], indices: [0,1,2]))
        scene.exchange.value.center = [3222.5,0,3273.5]
        scene.exchange.value.nodes = [RenderNode(geometry: selfGeometry, transform: scTranslation(scene.exchange.value.center))]
        actualRenderer.resize(to: BoundingBox(min: [-0.65,-0.45,-0.45], max: [0.65,0.45,0.45]))
        await actualRenderer.start()
        defer { actualRenderer.stop() }
        var retainedActorID: UInt64?
        var retainedMesh: LowLevelMesh?
        // Advance one live renderer through movement, elevation, zoom, and every
        // orientation. Restarting the fixture per case would hide stale updates.
        for center: SIMD3<Float> in [[3222.5,0,3273.5],[3222.5,12.75,3273.5],[3226.75,12.75,3279.25]] {
            for scale: Float in [1.3/34,0.08] {
                for turn in 0..<4 {
                    scene.exchange.value.center = center
                    scene.exchange.value.scale = scale
                    scene.exchange.value.tableQuarterTurns = turn
                    scene.exchange.value.nodes[0].transform = scTranslation(center)
                    try await pause()
                    let children = actualRenderer.gameRoot.children.filter(\.isEnabled)
                    precondition(children.count == 1, "Self actor fixture was not uploaded: \(actualRenderer.status)")
                    let actor = children.first!
                    let low = actor.components[ModelComponent.self]!.mesh.lowLevelMesh!
                    if let retainedActorID { precondition(actor.id == retainedActorID, "Live center/zoom/rotation update replaced the self actor entity") }
                    else { retainedActorID = actor.id }
                    if let retainedMesh { precondition(sharesVertexStorage(retainedMesh,low), "Live center/zoom/rotation update replaced the self actor mesh storage") }
                    else { retainedMesh = low }
                    var bakedFoot = SIMD3<Float>.zero
                    low.withUnsafeBytes(bufferIndex: 0) { bakedFoot = $0.bindMemory(to: NativeVertex.self)[0].position }
                    let boardCenter = scPoint(actualRenderer.gameRoot.transform.matrix, center)
                    let actualFoot = scPoint(actor.transformMatrix(relativeTo: actualRenderer.root), bakedFoot)
                    let expectedFoot = scPoint(actualRenderer.boardRoot.transform.matrix, .zero)
                    print("CENTER CHECK game=\(center) scale=\(scale) turn=\(turn) gameRoot(center)=\(boardCenter) bakedFoot=\(bakedFoot) actualSceneFoot=\(actualFoot) expectedSceneFoot=\(expectedFoot)")
                    precondition(simd_distance(bakedFoot,center) < 0.0001, "Actual self foot vertex did not update to the moving game center")
                    precondition(simd_length(boardCenter) < 0.001,
                                 "Absolute game center does not map to board origin: center=\(center), actual=\(boardCenter)")
                    precondition(simd_distance(actualFoot,expectedFoot) < 0.001 && abs(actualFoot.x) < 0.001 && abs(actualFoot.z) < 0.001,
                                 "The actual baked self actor is not centered inside the symmetric volume footprint after movement, zoom, and rotation")
                }
            }
        }
    }
    @MainActor static func pause() async throws {try await Task.sleep(for:.milliseconds(120))}
    @MainActor static func run() async throws {
        var envelope = VolumeVerticalEnvelope()
        precondition(envelope.update(minimum: -3.25, maximum: 4.21, now: 10))
        precondition(envelope.minimum == -3.3 && envelope.maximum == 4.3, "Envelope must expand immediately with outward rounding")
        envelope.update(minimum: -0.2, maximum: 0.4, now: 11.99)
        precondition(envelope.minimum == -3.3 && envelope.maximum == 4.3, "Recent extreme did not absorb bounds jitter")
        envelope.update(minimum: -0.2, maximum: 0.4, now: 12.01)
        precondition(envelope.minimum == VolumeVerticalEnvelope.defaultMinimum && envelope.maximum == VolumeVerticalEnvelope.defaultMaximum, "Expired mountain permanently shrank table")
        envelope.update(minimum: -5, maximum: 6, now: 13)
        envelope.reset()
        precondition(envelope.minimum == VolumeVerticalEnvelope.defaultMinimum && envelope.maximum == VolumeVerticalEnvelope.defaultMaximum, "New footprint/session retained historical extrema")
        try await verifyPlayerCenter()
        let scene=GameScene(),renderer=VolumetricTableRenderer(scene:scene)
        let mesh=NativeMesh(vertices:[
            NativeVertex(position:[-1,0,-1],color:[1,0,0,1]),
            NativeVertex(position:[1,0,-1],color:[0,1,0,1]),
            NativeVertex(position:[0,0,1],color:[0,0,1,1])],indices:[0,1,2])
        let first=RenderGeometry(mesh),second=RenderGeometry(mesh)
        scene.exchange.value.nodes=[RenderNode(geometry:first,transform:scTranslation([3200,0,3200]),tint:[0.5,1,1,1]),RenderNode(geometry:second,transform:scTranslation([3203,2,3200]))]
        renderer.resize(to:BoundingBox(min:[-0.65,-0.45,-0.45],max:[0.65,0.45,0.45]))
        await renderer.start();try await pause()
        var children=Array(renderer.gameRoot.children).filter(\.isEnabled)
        precondition(children.count==2,"Real LowLevelMesh scene did not appear: \(renderer.status)")
        let firstEntity=children.first{entity in
            guard let model=entity.components[ModelComponent.self],let low=model.mesh.lowLevelMesh else{return false}
            var x:Float=0;low.withUnsafeBytes(bufferIndex:0){x=$0.bindMemory(to:NativeVertex.self)[0].position.x};return x==3199
        }!
        let model=firstEntity.components[ModelComponent.self]!,low=model.mesh.lowLevelMesh!
        var vertices:[NativeVertex]=[]
        low.withUnsafeBytes(bufferIndex:0){vertices=Array($0.bindMemory(to:NativeVertex.self).prefix(3))}
        precondition(vertices[0].position == [3199,0,3199],"Node transform was not baked to game coordinates")
        precondition(vertices[0].color == [0.5,0,0,1],"Original vertex color/tint changed")
        precondition(vertices[1].color == [0,1,0,1],"Vertex colors collapsed to a material bucket")
        let shader=model.materials[0] as! ShaderGraphMaterial
        guard case .simd3Float(let center)=shader.getParameter(name:"gameCenter")! else{fatalError("Missing center")}
        precondition(center == scene.exchange.value.center)
        var edges:[SIMD3<Float>]=[]
        for i in 0..<8 {guard case .simd3Float(let e)=shader.getParameter(name:"edge\(i)")! else{fatalError("Missing edge")};edges.append(e)}
        var clips=0
        for ix in -20...20 {for iz in -20...20 {
            let p=SIMD2<Float>(Float(ix)*0.041,Float(iz)*0.039)
            let result=edges.allSatisfy{simd_dot($0,SIMD3(p.x,-p.y,1)) >= -0.00001}
            precondition(result==scInside(p,scene.exchange.value.boundary),"Graph edge orientation differs from Metal footprint")
            clips += 1
        }}
        for vertex in vertices {
            let p=scPoint(renderer.boardRoot.transform.matrix*renderer.gameRoot.transform.matrix,vertex.position)
            precondition(p.y > -0.45 && p.y < 0.45,"Below-player terrain escaped the system volume")
        }
        let originalBounds=renderer.boardRoot.visualBounds(relativeTo:renderer.root)
        precondition(originalBounds.extents.y>0,"Actual geometry bounds missing")
        renderer.resize(to:BoundingBox(min:[-0.35,-0.28,-0.28],max:[0.35,0.28,0.28]))
        for vertex in vertices {
            let p=scPoint(renderer.boardRoot.transform.matrix*renderer.gameRoot.transform.matrix,vertex.position)
            precondition(p.y > -0.28 && p.y < 0.28,"Resized volume clipped lower terrain")
        }
        // Rotation must fit the actual, off-center footprint into an offset
        // nonsquare system volume. A square centered fixture hides swapped-axis
        // and incorrect-centering bugs, while rebuilds can hide transform bugs.
        let savedSnapshot = scene.exchange.value
        let rotatedBounds = BoundingBox(min: [-0.45,-1.2,-0.6], max: [0.95,1.6,0.05])
        scene.exchange.value.boundary = [[-0.4,-0.15],[0.8,-0.15],[0.8,0.45],[-0.4,0.45]]
        renderer.resize(to: rotatedBounds)
        try await pause()
        let retainedIDs = Set(renderer.gameRoot.children.filter(\.isEnabled).map(\.id))
        let footprintCenter = SIMD3<Float>(0.2,0,0.15)
        let localPoint = SIMD3<Float>(0.53,0,-0.07)
        let clockwiseOffsets: [SIMD3<Float>] = [[0.33,0,-0.22],[0.22,0,0.33],[-0.33,0,0.22],[-0.22,0,-0.33]]
        let clockwiseEast: [SIMD3<Float>] = [[1,0,0],[0,0,1],[-1,0,0],[0,0,-1]]
        var fittedScales: [Float] = []
        for turn in 0..<4 {
            scene.exchange.value.tableQuarterTurns = turn
            try await pause()
            let transform = renderer.boardRoot.transform.matrix
            let fittedScale = renderer.boardRoot.scale.x
            fittedScales.append(fittedScale)
            for corner in scene.exchange.value.boundary {
                let point = scPoint(transform, SIMD3(corner.x,0,corner.y))
                precondition(point.x >= rotatedBounds.min.x-0.0001 && point.x <= rotatedBounds.max.x+0.0001 &&
                             point.y >= rotatedBounds.min.y-0.0001 && point.y <= rotatedBounds.max.y+0.0001 &&
                             point.z >= rotatedBounds.min.z-0.0001 && point.z <= rotatedBounds.max.z+0.0001,
                             "Quarter turn \(turn) clipped an actual footprint corner: \(point)")
            }
            let fittedCenter = scPoint(transform, footprintCenter)
            precondition(abs(fittedCenter.x-rotatedBounds.center.x) < 0.0001 && abs(fittedCenter.z-rotatedBounds.center.z) < 0.0001,
                         "Quarter turn \(turn) failed to center an off-origin footprint")
            let actualOffset = scPoint(transform, localPoint)-fittedCenter
            precondition(simd_distance(actualOffset, clockwiseOffsets[turn]*fittedScale) < 0.0001,
                         "Quarter turn \(turn) rotated the known board point in the wrong direction")
            precondition(simd_distance(scDirection(transform,[1,0,0]),clockwiseEast[turn]) < 0.0001,
                         "Quarter turn \(turn) did not rotate clockwise as seen from above")
            let recovered = scPoint(transform.inverse, scPoint(transform, localPoint))
            precondition(simd_distance(recovered,localPoint) < 0.0001,
                         "Quarter turn \(turn) inverse did not recover the original board tap point")
            let gamePoint = SIMD3<Float>(3204.125,11.25,3202.75)
            let sceneFromGame = transform*renderer.gameRoot.transform.matrix
            precondition(simd_distance(scPoint(sceneFromGame.inverse,scPoint(sceneFromGame,gamePoint)),gamePoint) < 0.002,
                         "Quarter turn \(turn) lost the game-world point through rendering and inverse input transforms")
            precondition(Set(renderer.gameRoot.children.filter(\.isEnabled).map(\.id)) == retainedIDs,
                         "Quarter turn \(turn) rebuilt or culled unchanged game geometry")
            precondition(sharesVertexStorage(low, firstEntity.components[ModelComponent.self]!.mesh.lowLevelMesh!),
                         "Quarter turn \(turn) reallocated the retained LowLevelMesh")
        }
        precondition(abs(fittedScales[1]*2-fittedScales[0]) < 0.0001 &&
                     abs(fittedScales[2]-fittedScales[0]) < 0.0001 && abs(fittedScales[3]-fittedScales[1]) < 0.0001,
                     "Odd quarter turns did not swap the long footprint side into the shorter volume axis")
        scene.exchange.value = savedSnapshot
        renderer.resize(to: BoundingBox(min:[-0.35,-0.28,-0.28],max:[0.35,0.28,0.28]))
        try await pause()
        let unzoomedTransform = renderer.gameRoot.transform.matrix
        let gameProbe = scene.exchange.value.center + SIMD3<Float>(2,1,-3)
        let unzoomedOffset = scPoint(unzoomedTransform, gameProbe)-scPoint(unzoomedTransform, scene.exchange.value.center)
        scene.exchange.value.scale = savedSnapshot.scale*1.25
        try await pause()
        let zoomedTransform = renderer.gameRoot.transform.matrix
        let zoomedOffset = scPoint(zoomedTransform, gameProbe)-scPoint(zoomedTransform, scene.exchange.value.center)
        precondition(simd_distance(zoomedOffset,unzoomedOffset*1.25) < 0.0001,
                     "Zoom failed to scale the actual game-world mapping by 1.25")
        precondition(scene.exchange.value.boundary == savedSnapshot.boundary,
                     "Zoom changed the physical table footprint")
        let zoomedMaterial = firstEntity.components[ModelComponent.self]!.materials[0] as! ShaderGraphMaterial
        guard case .float(let zoomedShaderScale) = zoomedMaterial.getParameter(name: "boardScale")! else { fatalError("Missing zoomed board scale") }
        precondition(abs(zoomedShaderScale-scene.exchange.value.scale) < 0.00001,
                     "Zoomed geometry and shader footprint use different scales")
        precondition(Set(renderer.gameRoot.children.filter(\.isEnabled).map(\.id)) == retainedIDs &&
                     sharesVertexStorage(low, firstEntity.components[ModelComponent.self]!.mesh.lowLevelMesh!),
                     "Zoom rebuilt immutable game geometry instead of changing its mapping")
        scene.exchange.value.scale = savedSnapshot.scale
        try await pause()
        var animated=mesh;animated.vertices[0].position.y=0.5
        scene.exchange.value.nodes[0]=RenderNode(geometry:RenderGeometry(animated),transform:scTranslation([3200,0,3200]))
        try await pause()
        children=Array(renderer.gameRoot.children).filter(\.isEnabled)
        precondition(children.contains{ $0.id == firstEntity.id },"Animation reallocated a compatible mesh entity")
        var updatedY: Float = -999
        low.withUnsafeBytes(bufferIndex:0){ updatedY = $0.bindMemory(to:NativeVertex.self)[0].position.y }
        precondition(updatedY == 0.5,"Previously retained LowLevelMesh buffer did not receive the new animation pose")
        let normalScale = renderer.boardRoot.scale.y
        scene.exchange.value.nodes.append(RenderNode(geometry:RenderGeometry(mesh),transform:scTranslation([3200,90,3200])))
        try await pause()
        let mountainScale = renderer.boardRoot.scale.y
        precondition(mountainScale < normalScale * 0.5, "Current tall scenery was not fitted immediately")
        scene.exchange.value.nodes.removeLast()
        try await pause()
        precondition(renderer.boardRoot.scale.y == mountainScale, "Bounds shrank on the first missing animation frame")
        try await Task.sleep(for:.milliseconds(2100))
        precondition(abs(renderer.boardRoot.scale.y - normalScale) < 0.0001, "Actual renderer did not recover size after scenery left")
        for vertex in vertices {
            let p=scPoint(renderer.boardRoot.transform.matrix*renderer.gameRoot.transform.matrix,vertex.position)
            precondition(p.y > -0.28 && p.y < 0.28, "Recovery cropped lower-floor geometry")
        }
        // Same immutable geometry, new transform: cached local bounds must follow it.
        scene.exchange.value.nodes[1]=RenderNode(geometry:second,transform:scTranslation([9000,2,9000]))
        try await pause()
        precondition(Array(renderer.gameRoot.children).filter(\.isEnabled).count==1,"Moving cached geometry used stale culling bounds")
        scene.exchange.value.nodes[1]=RenderNode(geometry:second,transform:scTranslation([3202,2,3200]))
        try await pause()
        precondition(Array(renderer.gameRoot.children).filter(\.isEnabled).count==2,"Returning cached geometry remained culled")
        // A wide billboard overlaps the footprint, but its center is outside.
        scene.exchange.value.nodes.append(RenderNode(geometry:RenderGeometry(mesh),transform:scTranslation([3208.4,10,3200]),billboard:true))
        try await pause()
        precondition(!renderer.boardRoot.children.contains{$0.components[BillboardComponent.self] != nil},"Billboard centered outside board was shown")
        // Fill the real 768-slot limit, then keep the same IDs in the streamed
        // snapshot while moving all but one outside the footprint. Place the new
        // visible node first to catch incorrect admission before classification.
        scene.exchange.value.nodes = (0..<768).map { index in
            RenderNode(geometry:RenderGeometry(mesh), transform:scTranslation([index == 767 ? 3202 : 3200, 0, 3200]))
        }
        try await pause()
        precondition(Array(renderer.gameRoot.children).filter(\.isEnabled).count == 768, "Capacity fixture did not fill real renderer slots")
        let survivor = renderer.gameRoot.children.first { entity in
            guard let low = entity.components[ModelComponent.self]?.mesh.lowLevelMesh else { return false }
            var x: Float = 0; low.withUnsafeBytes(bufferIndex:0) { x = $0.bindMemory(to:NativeVertex.self)[0].position.x }
            return x == 3201
        }!.id
        for index in 0..<767 { scene.exchange.value.nodes[index].transform = scTranslation([3300,0,3300]) }
        scene.exchange.value.nodes.insert(RenderNode(geometry:RenderGeometry(mesh),transform:scTranslation([3204,0,3200])), at:0)
        try await pause()
        let admitted = Array(renderer.gameRoot.children).filter(\.isEnabled)
        precondition(admitted.count == 2, "Hidden slots starved newly visible geometry at the real slot limit")
        precondition(admitted.contains { $0.id == survivor }, "Admission evicted current-frame visible geometry")
        precondition(admitted.contains { entity in
            guard let low = entity.components[ModelComponent.self]?.mesh.lowLevelMesh else { return false }
            var x: Float = 0; low.withUnsafeBytes(bufferIndex:0) { x = $0.bindMemory(to:NativeVertex.self)[0].position.x }
            return x == 3203
        }, "Newly visible mesh was not uploaded after hidden-slot reclamation")
        renderer.stop()
        precondition(renderer.gameRoot.children.isEmpty,"Closed volume retained visible mesh entities")
        print("PASS production RealityKit volume renderer: 24 live player-center and baked self-vertex cases across movement/elevation/zoom/rotation, transforms, per-vertex color/tint, \(clips) shader half-plane parity cases, lower-floor fit+resize, all four clockwise quarter turns with off-center nonsquare fit and inverse mapping without geometry reallocation, zoom mapping and shader-scale parity, two-second envelope shrink, immutable bounds movement, LowLevelMesh animation reuse, billboard footprint, hidden-slot pressure recovery, teardown")
        print("LIMIT: deterministic scene feed and real RealityKit resources on macOS; pixel colors/system move/resize/spatial gestures require visionOS runtime")
    }
}
