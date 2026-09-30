import Foundation
import RealityKit
import QuartzCore
import simd

/// Actual terrain surfaces and small actor targets for system gaze-and-pinch
/// picking. No enclosing collision box, camera access, or inferred gaze ray.
@MainActor final class VolumeInputController {
    let root = Entity()
    private let world = Entity()
    private weak var scene: GameScene?
    private var terrain: [String: TerrainSlot] = [:]
    private var actors: [String: ActorSlot] = [:]
    private var terrainIDs: Set<UInt64> = []
    private var actorIDs: [UInt64: String] = [:]
    private var cooking: Task<Void, Never>?
    private var failed: Set<String> = []
    private var wantedTerrain: Set<String> = []
    private var generation = 0
    private var epoch = -1
    private var lastUpdate: TimeInterval = 0
    private let byteLimit = 4 * 1024 * 1024
    private let terrainLimit = 64
    private let actorLimit = 256

    private struct TerrainSlot { let entity: Entity; let bytes: Int }
    private struct ActorSlot { let entity: Entity; var size: SIMD3<Float> }
    private struct SurfacePart { var positions: [SIMD3<Float>] = []; var indices: [UInt16] = [] }

    init(scene: GameScene) {
        self.scene = scene
        root.name = "TableScape map input"
        world.name = "Surface input geometry"
        root.addChild(world)
    }

    func stop() {
        generation += 1; cooking?.cancel(); cooking = nil
        terrain.removeAll(); actors.removeAll(); terrainIDs.removeAll(); actorIDs.removeAll(); failed.removeAll()
        world.children.removeAll(); wantedTerrain.removeAll(); lastUpdate = 0; epoch = -1
    }

    func update(snapshot: RenderSnapshot) {
        guard let scene, snapshot.scale.isFinite, snapshot.scale > 0 else { return }
        if epoch != scene.volumeInputEpoch { stop(); epoch = scene.volumeInputEpoch }
        // Shapes use mirrored game Z and positive scaling: physics meshes never
        // inherit the rendering hierarchy's negative scale.
        world.scale = SIMD3(repeating: snapshot.scale)
        world.position = SIMD3(-snapshot.center.x, -snapshot.center.y, snapshot.center.z) * snapshot.scale
        let now = CACurrentMediaTime()
        guard now - lastUpdate >= 0.1 else { return }
        lastUpdate = now
        guard scene.session.connected, snapshot.boundary.count >= 3 else {
            world.isEnabled = false; scene.setVolumeInputStatus("Connect to use the map"); return
        }
        world.isEnabled = true
        let minX = snapshot.center.x + (snapshot.boundary.map(\.x).min() ?? 0) / snapshot.scale
        let maxX = snapshot.center.x + (snapshot.boundary.map(\.x).max() ?? 0) / snapshot.scale
        let minZ = snapshot.center.z - (snapshot.boundary.map(\.y).max() ?? 0) / snapshot.scale
        let maxZ = snapshot.center.z - (snapshot.boundary.map(\.y).min() ?? 0) / snapshot.scale
        let minimum = SIMD2(minX, minZ), maximum = SIMD2(maxX, maxZ)
        let chunks = scene.volumeTerrainChunks.filter { chunk in
            let parts = chunk.key.split(separator: ":")
            guard parts.count == 3, let x = Float(parts[1]), let z = Float(parts[2]) else { return false }
            return x <= maximum.x && x + 16 >= minimum.x && z <= maximum.y && z + 16 >= minimum.y
        }.sorted { a, b in
            func distance(_ key: String) -> Float {
                let parts = key.split(separator: ":")
                guard parts.count == 3, let x = Float(parts[1]), let z = Float(parts[2]) else { return .infinity }
                return simd_length_squared(SIMD2(x + 8 - snapshot.center.x, z + 8 - snapshot.center.z))
            }
            return distance(a.key) < distance(b.key)
        }
        let wanted = Set(chunks.prefix(terrainLimit).map(\.key))
        wantedTerrain = wanted
        for key in Array(terrain.keys) where !wanted.contains(key) {
            if let slot = terrain.removeValue(forKey: key) { terrainIDs.remove(slot.entity.id); slot.entity.removeFromParent() }
        }
        failed.formIntersection(wanted)
        updateActors(scene.volumeTargets, minimum: minimum, maximum: maximum, center: snapshot.center)
        if cooking == nil, let chunk = chunks.prefix(terrainLimit).first(where: { terrain[$0.key] == nil && !failed.contains($0.key) }) {
            cook(key: chunk.key, meshes: chunk.meshes)
        }
        scene.setVolumeInputStatus(terrain.isEmpty ? "Preparing map input…" : "Map ready")
    }

    func pick(entity: Entity, point: SIMD3<Float>) {
        // Only this controller's live collision entities can send game actions.
        // Walking uses the actual surface location supplied by SpatialTapGesture.
        var candidate: Entity? = entity
        while let current = candidate, current !== root {
            if let identity = actorIDs[current.id] {
                scene?.selectVolumePoint(point, targetID: identity, terrain: false); return
            }
            if terrainIDs.contains(current.id) {
                scene?.selectVolumePoint(point, targetID: nil, terrain: true); return
            }
            candidate = current.parent
        }
    }

    private func updateActors(_ targets: [PickTarget], minimum: SIMD2<Float>, maximum: SIMD2<Float>, center: SIMD3<Float>) {
        var wanted = Set<String>()
        let sorted = targets.sorted {
            simd_length_squared(scPoint($0.transform, .zero) - center) < simd_length_squared(scPoint($1.transform, .zero) - center)
        }
        for target in sorted {
            guard wanted.count < actorLimit else { break }
            let identity = GameContract.identity(kind: target.kind, actor: target.actor)
            var low = SIMD3<Float>(repeating: .infinity), high = SIMD3<Float>(repeating: -.infinity)
            for mesh in target.meshes {
                var localLow = SIMD3<Float>(repeating: .infinity), localHigh = SIMD3<Float>(repeating: -.infinity)
                for vertex in mesh.vertices { localLow = simd_min(localLow, vertex.position); localHigh = simd_max(localHigh, vertex.position) }
                guard localLow.x.isFinite, localHigh.x.isFinite else { continue }
                for x in [localLow.x, localHigh.x] { for y in [localLow.y, localHigh.y] { for z in [localLow.z, localHigh.z] {
                    let point = scPoint(target.transform, SIMD3(x, y, z)); low = simd_min(low, point); high = simd_max(high, point)
                } } }
            }
            guard low.x.isFinite, high.x.isFinite else { continue }
            // Clip actor targets to the visible table rectangle. The action
            // method also checks the exact polygon before accepting any tap.
            low.x = max(low.x, minimum.x); high.x = min(high.x, maximum.x)
            low.z = max(low.z, minimum.y); high.z = min(high.z, maximum.y)
            guard high.x > low.x, high.z > low.z else { continue }
            let size = simd_max(high - low, SIMD3(0.02, 0.08, 0.02))
            var slot = actors[identity] ?? ActorSlot(entity: Entity(), size: .zero)
            if slot.size != size {
                slot.entity.components.set(CollisionComponent(shapes: [.generateBox(size: size)], mode: .trigger, filter: .default))
                slot.size = size
            }
            if slot.entity.parent == nil {
                slot.entity.components.set(InputTargetComponent())
                slot.entity.name = "Game action target"
                world.addChild(slot.entity); actorIDs[slot.entity.id] = identity
            }
            let midpoint = (low + high) * 0.5
            slot.entity.position = SIMD3(midpoint.x, midpoint.y, -midpoint.z)
            actors[identity] = slot; wanted.insert(identity)
        }
        for identity in Array(actors.keys) where !wanted.contains(identity) {
            if let slot = actors.removeValue(forKey: identity) { actorIDs[slot.entity.id] = nil; slot.entity.removeFromParent() }
        }
    }

    private func cook(key: String, meshes: [NativeMesh]) {
        let expected = generation
        guard let first = meshes.lazy.flatMap({ $0.vertices }).first(where: { $0.position.x.isFinite && $0.position.y.isFinite && $0.position.z.isFinite }) else {
            failed.insert(key); return
        }
        // RealityKit static-mesh cooking needs local geometry. Keep absolute
        // game coordinates on the entity transform, not thousands of units
        // inside the collision resource's vertex bounds.
        let origin = first.position
        let reflectedOrigin = SIMD3(origin.x, origin.y, -origin.z)
        // Only raw terrain vertices are cooked, once per chunk/session. Animated
        // actors use boxes above; only one asynchronous cook can be in flight.
        var parts: [SurfacePart] = [], part = SurfacePart()
        for mesh in meshes {
            for i in stride(from: 0, to: max(0, mesh.indices.count - 2), by: 3) {
                let indices = [mesh.indices[i], mesh.indices[i + 1], mesh.indices[i + 2]]
                guard indices.allSatisfy({ Int($0) < mesh.vertices.count }) else { continue }
                let points = indices.map { mesh.vertices[Int($0)].position }
                guard points.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }),
                      simd_length_squared(simd_cross(points[1] - points[0], points[2] - points[0])) > 0.00000001 else { continue }
                if part.positions.count + 3 > Int(UInt16.max) { parts.append(part); part = SurfacePart() }
                let base = UInt16(part.positions.count)
                part.positions.append(contentsOf: points.map {
                    let local = $0 - origin
                    return SIMD3(local.x, local.y, -local.z)
                })
                // Reflecting Z changes winding. Reverse faces so their original
                // outward side is retained for static-mesh hit testing.
                part.indices += [base, base + 2, base + 1]
            }
        }
        if !part.positions.isEmpty { parts.append(part) }
        let bytes = parts.reduce(0) { $0 + $1.positions.count * MemoryLayout<SIMD3<Float>>.stride + $1.indices.count * MemoryLayout<UInt16>.stride }
        guard bytes > 0, bytes <= byteLimit else { failed.insert(key); return }
        // A full cache is temporary. Retry after distant chunks are retired;
        // only invalid geometry or cooking failures enter the failed set.
        guard terrain.values.reduce(0, { $0 + $1.bytes }) + bytes <= byteLimit else { return }
        cooking = Task { [weak self] in
            do {
                var shapes: [ShapeResource] = []
                for part in parts {
                    try Task.checkCancellation()
                    shapes.append(try await ShapeResource.generateStaticMesh(positions: part.positions, faceIndices: part.indices))
                }
                guard let self, self.generation == expected, !Task.isCancelled else { return }
                guard self.wantedTerrain.contains(key) else { self.cooking = nil; return }
                let entity = Entity()
                entity.name = "Walkable terrain"
                entity.position = reflectedOrigin
                entity.components.set(CollisionComponent(shapes: shapes, filter: .default))
                entity.components.set(InputTargetComponent())
                self.world.addChild(entity)
                self.terrain[key] = TerrainSlot(entity: entity, bytes: bytes)
                self.terrainIDs.insert(entity.id)
                self.cooking = nil
            } catch {
                guard let self, self.generation == expected else { return }
                self.failed.insert(key); self.cooking = nil
            }
        }
    }
}
