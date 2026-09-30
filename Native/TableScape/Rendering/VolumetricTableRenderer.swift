import Foundation
import Combine
import RealityKit
import Metal
import simd
import ImageIO
import CoreGraphics
import QuartzCore

/// A short history absorbs animated bounds jitter while letting the table recover
/// its normal size after tall/deep scenery leaves. The renderer samples at most
/// once per 33ms; 128 samples is a hard bound beyond the two-second window.
struct VolumeVerticalEnvelope {
    static let defaultMinimum: Float = -0.32
    static let defaultMaximum: Float = 0.58
    private(set) var minimum = defaultMinimum
    private(set) var maximum = defaultMaximum
    private struct Sample { let time: TimeInterval; let minimum: Float; let maximum: Float }
    private var samples: [Sample] = []

    mutating func reset() {
        samples.removeAll(keepingCapacity: true)
        minimum = Self.defaultMinimum; maximum = Self.defaultMaximum
    }
    @discardableResult mutating func update(minimum currentMinimum: Float, maximum currentMaximum: Float, now: TimeInterval) -> Bool {
        if let last = samples.last, now < last.time { reset() }
        samples.removeAll { now - $0.time >= 2 }
        samples.append(Sample(time: now, minimum: currentMinimum, maximum: currentMaximum))
        if samples.count > 128 { samples.removeFirst(samples.count - 128) }
        let low = samples.reduce(Self.defaultMinimum) { min($0, $1.minimum) }
        let high = samples.reduce(Self.defaultMaximum) { max($0, $1.maximum) }
        let nextMinimum = low < Self.defaultMinimum ? floor(low * 10) / 10 : Self.defaultMinimum
        let nextMaximum = high > Self.defaultMaximum ? ceil(high * 10) / 10 : Self.defaultMaximum
        let changed = nextMinimum != minimum || nextMaximum != maximum
        minimum = nextMinimum; maximum = nextMaximum
        return changed
    }
}

/// Presents the same native scene as real geometry in a movable system volume.
/// The volume owns no game simulation or ARKit session. Immutable scenery is
/// uploaded once; expired animated meshes donate their LowLevelMesh storage.
@MainActor final class VolumetricTableRenderer: ObservableObject {
    @Published private(set) var status = "Preparing 3D table…"
    let root = Entity()
    let boardRoot = Entity()
    let gameRoot = Entity()
    let input: Entity
    private let inputController: VolumeInputController
    private let rim = Entity()
    private weak var scene: GameScene?
    private var task: Task<Void, Never>?
    private var generation = 0
    private var baseMaterial: ShaderGraphMaterial?
    private var materials: [MaterialKey: ShaderGraphMaterial] = [:]
    private var textures: [Int: TextureResource] = [:]
    private var entries: [UUID: Slot] = [:]
    private var spare: [Slot] = []
    private var boundsCache: [UUID: BoundingBox] = [:]
    private var sceneBounds = BoundingBox(min: [-0.65, -0.45, -0.45], max: [0.65, 0.45, 0.45])
    private var lastBoundary: [SIMD2<Float>] = []
    private var lastCenter = SIMD3<Float>(repeating: .infinity)
    private var lastScale: Float = 0
    private var lastStatus: TimeInterval = 0
    private var materialVersion = 0
    private var verticalEnvelope = VolumeVerticalEnvelope()
    private var verticalMinimum: Float { verticalEnvelope.minimum }
    private var verticalMaximum: Float { verticalEnvelope.maximum }
    private var sessionEpoch = -1
    private let byteLimit = 80 * 1024 * 1024
    private let uploadLimit = 16 * 1024 * 1024
    private let slotLimit = 768

    private struct MaterialKey: Hashable { let texture: Int; let billboard: Bool }
    @MainActor private final class Slot {
        let mesh: LowLevelMesh
        let resource: MeshResource
        let entity = Entity()
        let bytes: Int
        var materialVersion = -1
        var materialKey = MaterialKey(texture: -999, billboard: false)
        var sourceID: UUID?
        var sourceTransform = matrix_identity_float4x4
        var sourceTint = SIMD4<Float>.zero
        static func allocationBytes(vertices: Int, indices: Int) -> Int {
            max(64, (vertices+63) & ~63) * MemoryLayout<NativeVertex>.stride + max(192, (indices+191)/192*192) * 4
        }
        init(vertices: Int, indices: Int) throws {
            let vertexCapacity = max(64, (vertices + 63) & ~63)
            let indexCapacity = max(192, (indices + 191) / 192 * 192)
            var descriptor = LowLevelMesh.Descriptor(vertexCapacity: vertexCapacity, indexCapacity: indexCapacity)
            descriptor.vertexAttributes = [
                .init(semantic: .position, format: .float3, offset: MemoryLayout<NativeVertex>.offset(of: \.position)!),
                .init(semantic: .color, format: .float4, offset: MemoryLayout<NativeVertex>.offset(of: \.color)!),
                .init(semantic: .uv0, format: .float2, offset: MemoryLayout<NativeVertex>.offset(of: \.uv)!)
            ]
            descriptor.vertexLayouts = [.init(bufferIndex: 0, bufferStride: MemoryLayout<NativeVertex>.stride)]
            mesh = try LowLevelMesh(descriptor: descriptor)
            resource = try MeshResource(from: mesh)
            bytes = vertexCapacity * MemoryLayout<NativeVertex>.stride + indexCapacity * 4
        }
        func fits(_ source: NativeMesh) -> Bool { mesh.vertexCapacity >= source.vertices.count && mesh.indexCapacity >= source.indices.count }
    }

    init(scene: GameScene) {
        self.scene = scene
        inputController = VolumeInputController(scene: scene)
        input = inputController.root
        root.name = "TableScape volume"
        root.addChild(boardRoot); boardRoot.addChild(gameRoot); boardRoot.addChild(input); boardRoot.addChild(rim)
    }

    func start() async {
        guard task == nil else { return }
        generation += 1; let expected = generation
        do {
            let material = try await ShaderGraphMaterial(named: VolumeMaterialSource.name, from: VolumeMaterialSource.data())
            guard expected == generation, !Task.isCancelled else { return }
            baseMaterial = material
            textures[-1] = try makeTexture(nil)
            task = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    self.update()
                    do { try await Task.sleep(for: .milliseconds(33)) } catch { return }
                }
            }
        } catch {
            if expected == generation { status = "3D table unavailable: \(error.localizedDescription)" }
        }
    }

    func stop() {
        generation += 1; task?.cancel(); task = nil
        inputController.stop()
        for slot in entries.values { slot.entity.removeFromParent() }
        entries.removeAll(); spare.removeAll(); boundsCache.removeAll()
        materials.removeAll(); textures.removeAll(); baseMaterial = nil
        lastCenter = SIMD3(repeating: .infinity); lastScale = 0
        verticalEnvelope.reset(); sessionEpoch = -1
        status = "Preparing 3D table…"
    }

    /// Bounds are relative to `root`, not the window scene origin.
    func resize(to bounds: BoundingBox) {
        guard bounds.extents.x > 0.05, bounds.extents.y > 0.05, bounds.extents.z > 0.05 else { return }
        sceneBounds = bounds
        fit(boundary: scene?.exchange.read().boundary ?? [])
    }

    private func fit(boundary: [SIMD2<Float>]) {
        guard !boundary.isEmpty else { return }
        let minX = boundary.map(\.x).min() ?? -0.65, maxX = boundary.map(\.x).max() ?? 0.65
        let minZ = boundary.map(\.y).min() ?? -0.45, maxZ = boundary.map(\.y).max() ?? 0.45
        let width = max(0.2, maxX-minX), depth = max(0.2, maxZ-minZ)
        let turns = scene?.exchange.read().tableQuarterTurns ?? 0
        let orientation = simd_quatf(angle: -Float(turns) * .pi / 2, axis: [0, 1, 0])
        let rotatedWidth = turns % 2 == 0 ? width : depth
        let rotatedDepth = turns % 2 == 0 ? depth : width
        let fit = max(0.01, min(sceneBounds.extents.x/rotatedWidth, sceneBounds.extents.z/rotatedDepth, sceneBounds.extents.y/max(0.9, verticalMaximum-verticalMinimum)) * 0.94)
        let center = SIMD3((minX+maxX)*0.5, (verticalMinimum+verticalMaximum)*0.5, (minZ+maxZ)*0.5)
        // Rendered geometry and collision surfaces share this rotated parent.
        // Spatial taps convert back to its local space before resolving game actions.
        boardRoot.orientation = orientation
        boardRoot.scale = SIMD3(repeating: fit)
        boardRoot.position = sceneBounds.center - orientation.act(center * fit)
        if boundary != lastBoundary {
            rim.children.removeAll()
            let material = UnlitMaterial(color: .init(red: 0.58, green: 0.37, blue: 0.15, alpha: 1), applyPostProcessToneMap: false)
            for index in boundary.indices {
                let a = boundary[index], b = boundary[(index+1)%boundary.count], d = b-a
                let rail = ModelEntity(mesh: .generateBox(size: [simd_length(d), 0.009, 0.009]), materials: [material])
                rail.position = [(a.x+b.x)/2, -0.008, (a.y+b.y)/2]
                rail.orientation = simd_quatf(angle: -atan2(d.y, d.x), axis: [0,1,0])
                rim.addChild(rail)
            }
        }
    }

    func tap(entity: Entity, point: SIMD3<Float>) {
        inputController.pick(entity: entity, point: point)
    }

    private func update() {
        guard let scene, baseMaterial != nil else { return }
        let began = CACurrentMediaTime(), snapshot = scene.exchange.read()
        if sessionEpoch != scene.session.sessionEpoch || snapshot.scale != lastScale || snapshot.boundary != lastBoundary {
            sessionEpoch = scene.session.sessionEpoch; verticalEnvelope.reset()
        }
        fit(boundary: snapshot.boundary)
        inputController.update(snapshot: snapshot)
        gameRoot.transform = Transform(matrix: scScale(SIMD3(snapshot.scale, snapshot.scale, -snapshot.scale)) * scTranslation(-snapshot.center))
        let changed = snapshot.center != lastCenter || snapshot.scale != lastScale || snapshot.boundary != lastBoundary
        if changed { materialVersion += 1; lastCenter = snapshot.center; lastScale = snapshot.scale; lastBoundary = snapshot.boundary }
        let active = Set(snapshot.nodes.map { $0.geometry.id })
        for id in Array(entries.keys) where !active.contains(id) {
            if let slot = entries.removeValue(forKey: id) { slot.entity.removeFromParent(); spare.append(slot) }
        }
        boundsCache = boundsCache.filter { active.contains($0.key) }
        // Classify the whole current frame before admission. A previously visible
        // slot can now be hidden even when it occurs later in snapshot.nodes.
        var visibleNodes: [(node: RenderNode, bounds: BoundingBox)] = []
        var visibleIDs = Set<UUID>()
        visibleNodes.reserveCapacity(snapshot.nodes.count)
        for node in snapshot.nodes {
            let source = node.geometry.mesh, id = node.geometry.id
            guard !source.vertices.isEmpty, !source.indices.isEmpty else { continue }
            let local = boundsCache[id] ?? localBounds(source)
            boundsCache[id] = local
            let bounds = worldBounds(node, local: local)
            let billboardPosition = (scPoint(node.transform, .zero)-snapshot.center)*snapshot.scale
            let inside = node.billboard ? scInside(SIMD2(billboardPosition.x,-billboardPosition.z), snapshot.boundary) : intersects(bounds, snapshot: snapshot)
            if inside { visibleNodes.append((node, bounds)); visibleIDs.insert(id) }
        }
        for (id, slot) in entries where !visibleIDs.contains(id) { slot.entity.isEnabled = false }
        let usedTextures = Set(snapshot.nodes.map { $0.geometry.mesh.textureID }).union([-1])
        textures = textures.filter { usedTextures.contains($0.key) }
        materials = materials.filter { usedTextures.contains($0.key.texture) }
        var loadedTexture = false
        do {
            for id in usedTextures where id >= 0 && textures[id] == nil {
                if let data = snapshot.textures[id] { textures[id] = try makeTexture(data); loadedTexture = true }
            }
            if loadedTexture { materialVersion += 1 }
            let keys = Set(snapshot.nodes.map { MaterialKey(texture: textures[$0.geometry.mesh.textureID] == nil ? -1 : $0.geometry.mesh.textureID, billboard: $0.billboard) })
            for key in keys where changed || loadedTexture || materials[key] == nil { materials[key] = try material(key, snapshot: snapshot) }
            var uploaded = 0, shown = 0, triangles = 0, deferred = 0
            var minimumY = VolumeVerticalEnvelope.defaultMinimum, maximumY = VolumeVerticalEnvelope.defaultMaximum
            for (node, bounds) in visibleNodes {
                let source = node.geometry.mesh, id = node.geometry.id
                minimumY = min(minimumY, (bounds.min.y-snapshot.center.y)*snapshot.scale-0.035)
                maximumY = max(maximumY, (bounds.max.y-snapshot.center.y)*snapshot.scale+0.035)
                var slot = entries[id]
                if slot == nil {
                    let uploadBytes = source.vertices.count * MemoryLayout<NativeVertex>.stride + source.indices.count * 4
                    guard uploaded + uploadBytes <= uploadLimit else { deferred += 1; continue }
                    reclaimHiddenSlots(for: source, protecting: visibleIDs)
                    guard entries.count < slotLimit else { deferred += 1; continue }
                    if let index = spare.indices.filter({spare[$0].fits(source)}).min(by: {spare[$0].bytes < spare[$1].bytes}) {
                        slot = spare.remove(at: index)
                    } else {
                        let required = Slot.allocationBytes(vertices: source.vertices.count, indices: source.indices.count)
                        let liveBytes = entries.values.reduce(0) { $0+$1.bytes }
                        // Discard only unused buffer storage; never evict visible geometry mid-frame.
                        if liveBytes + required + spare.reduce(0, {$0+$1.bytes}) > byteLimit { spare.removeAll() }
                        guard entries.count < slotLimit, liveBytes + required < byteLimit else { deferred += 1; continue }
                        slot = try Slot(vertices: source.vertices.count, indices: source.indices.count)
                    }
                    if let slot { entries[id] = slot }
                }
                guard let slot else { continue }
                let geometryChanged = slot.sourceID != id || slot.sourceTransform != node.transform || slot.sourceTint != node.tint
                if geometryChanged {
                    let bytes = source.vertices.count * MemoryLayout<NativeVertex>.stride + source.indices.count * 4
                    guard uploaded + bytes <= uploadLimit else { slot.entity.isEnabled = false; deferred += 1; continue }
                    upload(node, to: slot, bounds: bounds); uploaded += bytes
                }
                let key = MaterialKey(texture: textures[source.textureID] == nil ? -1 : source.textureID, billboard: node.billboard)
                if slot.materialVersion != materialVersion || slot.materialKey != key || slot.entity.components[ModelComponent.self] == nil {
                    if let material = materials[key] { slot.entity.components.set(ModelComponent(mesh: slot.resource, materials: [material])) }
                    slot.materialVersion = materialVersion; slot.materialKey = key
                }
                if node.billboard {
                    if slot.entity.parent !== boardRoot { slot.entity.removeFromParent(); boardRoot.addChild(slot.entity) }
                    slot.entity.position = scPoint(gameRoot.transform.matrix, scPoint(node.transform, .zero))
                    slot.entity.scale = SIMD3(repeating: snapshot.scale)
                    slot.entity.components.set(BillboardComponent())
                } else {
                    if slot.entity.parent !== gameRoot { slot.entity.removeFromParent(); gameRoot.addChild(slot.entity) }
                    slot.entity.transform = .identity
                    slot.entity.components.remove(BillboardComponent.self)
                }
                slot.entity.isEnabled = true; shown += 1; triangles += source.indices.count/3
            }
            // Expand immediately to include lower terrain/roofs, but expire old
            // extremes after two seconds so distant mountains cannot shrink the
            // table permanently. Quantization and history avoid idle-frame jitter.
            if verticalEnvelope.update(minimum: minimumY, maximum: maximumY, now: began) {
                fit(boundary: snapshot.boundary)
            }
            while spare.count > 24 || spare.reduce(0, {$0+$1.bytes}) > 16*1024*1024 { spare.removeLast() }
            if began-lastStatus > 1 {
                lastStatus = began
                status = shown > 0 ? "3D table · \(shown) meshes · \(triangles.formatted()) triangles" : "Waiting for game world…"
                if deferred > 0 { status += " · loading \(deferred) meshes" }
                if ProcessInfo.processInfo.arguments.contains("--tablescape-profile") {
                    print("TABLESCAPE_VOLUME meshes=\(shown) triangles=\(triangles) uploadBytes=\(uploaded) retainedBytes=\(entries.values.reduce(0, {$0+$1.bytes})+spare.reduce(0, {$0+$1.bytes})) updateMS=\((CACurrentMediaTime()-began)*1000)")
                }
            }
        } catch { status = "3D table unavailable: \(error.localizedDescription)" }
    }

    /// Keep hidden buffers cached while there is room, but never let old views
    /// starve newly visible terrain/actors. Current-frame visibility protects
    /// every visible slot, including nodes not yet processed in the upload loop.
    private func reclaimHiddenSlots(for source: NativeMesh, protecting visibleIDs: Set<UUID>) {
        let required = Slot.allocationBytes(vertices: source.vertices.count, indices: source.indices.count)
        var liveBytes = entries.values.reduce(0) { $0 + $1.bytes }
        func canAdmit() -> Bool {
            entries.count < slotLimit && (spare.contains { $0.fits(source) } || liveBytes + required < byteLimit)
        }
        guard !canAdmit() else { return }
        let hidden = entries.filter { !visibleIDs.contains($0.key) }.sorted { $0.value.bytes > $1.value.bytes }
        for (id, slot) in hidden {
            entries[id] = nil; slot.entity.removeFromParent(); slot.entity.isEnabled = false
            liveBytes -= slot.bytes; spare.append(slot)
            if canAdmit() { break }
        }
    }

    private func upload(_ node: RenderNode, to slot: Slot, bounds: BoundingBox) {
        let source = node.geometry.mesh
        slot.mesh.replaceUnsafeMutableBytes(bufferIndex: 0) { bytes in
            let target = bytes.bindMemory(to: NativeVertex.self)
            for index in source.vertices.indices {
                var vertex = source.vertices[index]
                if !node.billboard { vertex.position = scPoint(node.transform, vertex.position) }
                vertex.color *= node.tint
                target[index] = vertex
            }
        }
        slot.mesh.replaceUnsafeMutableIndices { bytes in source.indices.withUnsafeBytes { bytes.copyBytes(from: $0) } }
        let meshBounds = node.billboard ? localBounds(source) : bounds
        slot.mesh.parts.replaceAll([.init(indexCount: source.indices.count, topology: .triangle, bounds: meshBounds)])
        slot.sourceID = node.geometry.id; slot.sourceTransform = node.transform; slot.sourceTint = node.tint
    }

    private func material(_ key: MaterialKey, snapshot: RenderSnapshot) throws -> ShaderGraphMaterial {
        var value = materials[key] ?? baseMaterial!
        value.faceCulling = .none
        value.readsDepth = true; value.writesDepth = true
        try value.setParameter(name: "gameTexture", value: .textureResource(textures[key.texture] ?? textures[-1]!))
        try value.setParameter(name: "gameCenter", value: .simd3Float(snapshot.center))
        try value.setParameter(name: "boardScale", value: .float(snapshot.scale))
        try value.setParameter(name: "clipEnabled", value: .float(key.billboard ? 0 : 1))
        try value.setParameter(name: "alphaThreshold", value: .float(key.billboard ? 0.005 : 0.2))
        let points = snapshot.boundary
        var signedArea: Float = 0
        if points.count >= 3 { for index in points.indices { let a=points[index], b=points[(index+1)%points.count]; signedArea += a.x*b.y-b.x*a.y } }
        let sign: Float = signedArea >= 0 ? 1 : -1
        for index in 0..<8 {
            var edge = SIMD3<Float>(0,0,1)
            if index < points.count, points.count >= 3 {
                let a=points[index],b=points[(index+1)%points.count],d=b-a
                // Shader uses game +Z; the board uses -Z.
                edge = SIMD3(-d.y, -d.x, d.y*a.x-d.x*a.y) * sign
            }
            try value.setParameter(name: "edge\(index)", value: .simd3Float(edge))
        }
        return value
    }

    private func localBounds(_ mesh: NativeMesh) -> BoundingBox {
        var minimum = SIMD3<Float>(repeating: .infinity), maximum = SIMD3<Float>(repeating: -.infinity)
        for vertex in mesh.vertices { minimum=simd_min(minimum,vertex.position);maximum=simd_max(maximum,vertex.position) }
        return BoundingBox(min: minimum-SIMD3(repeating:0.001), max: maximum+SIMD3(repeating:0.001))
    }
    private func worldBounds(_ node: RenderNode, local: BoundingBox) -> BoundingBox {
        var minimum = SIMD3<Float>(repeating: .infinity), maximum = SIMD3<Float>(repeating: -.infinity)
        for x in [local.min.x,local.max.x] { for y in [local.min.y,local.max.y] { for z in [local.min.z,local.max.z] {
            let p=scPoint(node.transform,SIMD3(x,y,z));minimum=simd_min(minimum,p);maximum=simd_max(maximum,p)
        } } }
        return BoundingBox(min: minimum, max: maximum)
    }
    private func intersects(_ bounds: BoundingBox, snapshot: RenderSnapshot) -> Bool {
        let minX=snapshot.boundary.map(\.x).min() ?? -0.65,maxX=snapshot.boundary.map(\.x).max() ?? 0.65
        let minZ=snapshot.boundary.map(\.y).min() ?? -0.45,maxZ=snapshot.boundary.map(\.y).max() ?? 0.45
        let a=(bounds.min-snapshot.center)*snapshot.scale,b=(bounds.max-snapshot.center)*snapshot.scale
        return b.x >= minX && a.x <= maxX && -a.z >= minZ && -b.z <= maxZ
    }
    private func makeTexture(_ data: Data?) throws -> TextureResource {
        let image = try VolumeTextureImage.decode(data)
        return try TextureResource(image:image,options:.init(semantic:.raw))
    }
}
