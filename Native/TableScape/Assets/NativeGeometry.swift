import Foundation
import simd

/// GPU interleaved vertex. SIMD3 stride is 16; mirror this layout in Metal.
struct NativeVertex: Sendable {
    var position: SIMD3<Float>
    var color: SIMD4<Float>
    var uv: SIMD2<Float>
    init(position: SIMD3<Float>, color: SIMD4<Float>, uv: SIMD2<Float> = .zero) {
        self.position = position; self.color = color; self.uv = uv
    }
}

struct NativeMesh: Sendable {
    var vertices: [NativeVertex]
    var indices: [UInt32]
    var textureID: Int = -1
    // Labels belong to split render vertices, so alpha and geometry transforms remain faithful.
    var vertexLabels: [Int] = []
    var faceLabels: [Int] = []
    var priorities: [Int] = []
    var sourceVertices: [Int] = []
    // Original recolored cache values and flags, once per ordered render triangle.
    var faceColors: [Int] = []
    var faceRenderTypes: [Int] = []
    var sourceModel: Int = -1
    var slot: Int = -1
    var byteCount: Int { vertices.count * MemoryLayout<NativeVertex>.stride + indices.count * MemoryLayout<UInt32>.stride + (vertexLabels.count + faceLabels.count + priorities.count + sourceVertices.count + faceColors.count + faceRenderTypes.count) * MemoryLayout<Int>.stride }
}

enum NativeAssetError: LocalizedError {
    case malformed(String), missing(String), integrity(String), unsupported(Int)
    var errorDescription: String? {
        switch self {
        case .malformed(let why): return "Invalid original asset: \(why)"
        case .missing(let path): return "Original asset unavailable: \(path)"
        case .integrity(let path): return "Asset verification failed: \(path)"
        case .unsupported(let version): return "Unsupported asset revision \(version)"
        }
    }
}

private struct CacheReader {
    let bytes: [UInt8]
    var offset: Int
    let end: Int
    init(_ bytes: [UInt8], start: Int, count: Int) throws {
        guard start >= 0, count >= 0, start <= bytes.count - count else { throw NativeAssetError.malformed("section bounds") }
        self.bytes = bytes; offset = start; end = start + count
    }
    mutating func u8() throws -> Int {
        guard offset < end else { throw NativeAssetError.malformed("truncated section") }
        defer { offset += 1 }; return Int(bytes[offset])
    }
    mutating func u16() throws -> Int { try (u8() << 8) | u8() }
    mutating func smart() throws -> Int {
        guard offset < end else { throw NativeAssetError.malformed("truncated delta") }
        return try bytes[offset] < 128 ? u8() - 64 : u16() - 49152
    }
}

/// Original revision 274 OB2, preserving labels, flat flags, texture bases and priorities.
struct NativeModel: Sendable {
    var id: Int = -1
    var positions: [SIMD3<Float>]
    var faces: [SIMD3<Int>]
    var colors: [Int]
    var renderTypes: [Int]
    var alpha: [Int]
    var priorities: [Int]
    var vertexLabels: [Int]
    var faceLabels: [Int]
    var textureBases: [SIMD3<Int>]
    var byteCount: Int { positions.count * 32 + faces.count * 96 + textureBases.count * 24 }

    static func decode(_ data: Data, id: Int = -1) throws -> NativeModel {
        guard data.count >= 18, data.count <= 16_000_000 else { throw NativeAssetError.malformed("model length") }
        let bytes = [UInt8](data)
        var footer = try CacheReader(bytes, start: bytes.count - 18, count: 18)
        let nv = try footer.u16(), nf = try footer.u16(), nt = try footer.u8()
        let types = try footer.u8(), priority = try footer.u8(), hasAlpha = try footer.u8(), fl = try footer.u8(), vl = try footer.u8()
        guard types <= 1, hasAlpha <= 1, fl <= 1, vl <= 1 else { throw NativeAssetError.malformed("model flags") }
        let nx = try footer.u16(), ny = try footer.u16(), nz = try footer.u16(), ni = try footer.u16()
        var cursor = 0
        func section(_ length: Int) throws -> CacheReader {
            defer { cursor += length }
            return try CacheReader(bytes, start: cursor, count: length)
        }
        var flags = try section(nv), orders = try section(nf)
        var priorities = try section(priority == 255 ? nf : 0), faceLabels = try section(fl == 1 ? nf : 0)
        var modes = try section(types == 1 ? nf : 0), vertexLabels = try section(vl == 1 ? nv : 0)
        var alphas = try section(hasAlpha == 1 ? nf : 0), indices = try section(ni)
        var colors = try section(nf * 2), textures = try section(nt * 6)
        var dx = try section(nx), dy = try section(ny), dz = try section(nz)
        guard cursor == bytes.count - 18 else { throw NativeAssetError.malformed("section length mismatch") }
        var m = NativeModel(id: id, positions: [], faces: [], colors: [], renderTypes: [], alpha: [], priorities: [], vertexLabels: [], faceLabels: [], textureBases: [])
        m.positions.reserveCapacity(nv); m.faces.reserveCapacity(nf)
        var x = 0, y = 0, z = 0
        for _ in 0..<nv {
            let flag = try flags.u8()
            guard flag <= 7 else { throw NativeAssetError.malformed("vertex flags") }
            if flag & 1 != 0 { x += try dx.smart() }; if flag & 2 != 0 { y += try dy.smart() }; if flag & 4 != 0 { z += try dz.smart() }
            m.positions.append(SIMD3(Float(x), -Float(y), Float(z)) / 128)
            m.vertexLabels.append(try vl == 1 ? vertexLabels.u8() : -1)
        }
        for _ in 0..<nf {
            m.colors.append(try colors.u16())
            let mode = try types == 1 ? modes.u8() : 0
            guard mode & 2 == 0 || mode >> 2 < nt else { throw NativeAssetError.malformed("texture basis index") }
            m.renderTypes.append(mode); m.priorities.append(try priority == 255 ? priorities.u8() : priority)
            m.alpha.append(try hasAlpha == 1 ? alphas.u8() : 0); m.faceLabels.append(try fl == 1 ? faceLabels.u8() : -1)
        }
        var a = 0, b = 0, c = 0, last = 0
        for _ in 0..<nf {
            switch try orders.u8() {
            case 1: a = try indices.smart() + last; b = try indices.smart() + a; c = try indices.smart() + b
            case 2: b = c; c = try indices.smart() + last
            case 3: a = c; c = try indices.smart() + last
            case 4: swap(&a, &b); c = try indices.smart() + last
            default: throw NativeAssetError.malformed("face order")
            }
            guard a >= 0, b >= 0, c >= 0, a < nv, b < nv, c < nv else { throw NativeAssetError.malformed("face vertex index") }
            m.faces.append(SIMD3(a,b,c)); last = c
        }
        for _ in 0..<nt {
            let p = try textures.u16(), u = try textures.u16(), v = try textures.u16()
            guard p < nv, u < nv, v < nv else { throw NativeAssetError.malformed("texture vertex index") }
            m.textureBases.append(SIMD3(p,u,v))
        }
        return m
    }

    func textureUV(face: Int, vertex: Int) -> SIMD2<Float> {
        let basis = textureBases[renderTypes[face] >> 2], p = positions[basis.x]
        let u = positions[basis.y] - p, v = positions[basis.z] - p, d = positions[vertex] - p
        let uu = simd_dot(u,u), vv = simd_dot(v,v), uv = simd_dot(u,v), du = simd_dot(d,u), dv = simd_dot(d,v)
        let det = uu * vv - uv * uv
        return abs(det) < 1e-10 ? .zero : SIMD2((du * vv - dv * uv) / det, (dv * uu - du * uv) / det)
    }

    func mesh(recolors: [Int: Int] = [:], recolorPairs: [SIMD2<Int>] = [], mirrored: Bool = false, lit: Bool = false, ambient: Int = 64, contrast: Int = 768, lightingTransform: simd_float3x3 = matrix_identity_float3x3) -> [NativeMesh] {
        var groups: [Int: NativeMesh] = [:]
        // Stable priority order retains the cache's face priority metadata for a renderer transparency pass.
        let faceOrder = faces.indices.sorted { priorities[$0] == priorities[$1] ? $0 < $1 : priorities[$0] < priorities[$1] }
        for f in faceOrder {
            var packed = colors[f]
            if recolorPairs.isEmpty { packed = recolors[packed] ?? packed }
            else { for pair in recolorPairs where packed == pair.x { packed = pair.y } }
            // On textured faces the recoloured face value is a texture ID (doors change stone to wood).
            let textured = renderTypes[f] & 2 != 0, texture = textured ? packed : -1
            var m = groups.removeValue(forKey: texture) ?? NativeMesh(vertices: [], indices: [], textureID: texture, sourceModel: id)
            let base = UInt32(m.vertices.count), face = faces[f]
            for original in [face.x,face.y,face.z] {
                var color = textured ? SIMD4<Float>(repeating: 1) : Self.palette(packed)
                color.w = Float(255-alpha[f]) / 255
                var p = positions[original]; if mirrored { p.z = -p.z }
                m.vertices.append(NativeVertex(position:p,color:color,uv:textured ? textureUV(face:f,vertex:original) : .zero))
                m.vertexLabels.append(vertexLabels[original]); m.faceLabels.append(faceLabels[f]); m.sourceVertices.append(original)
            }
            m.indices.append(contentsOf: mirrored ? [base,base+1,base+2] : [base,base+2,base+1]); m.priorities.append(priorities[f])
            m.faceColors.append(packed); m.faceRenderTypes.append(renderTypes[f])
            groups[texture] = m
        }
        let meshes = groups.keys.sorted().compactMap { groups[$0] }
        return lit ? NativeModelLighting.shade(meshes:meshes,lighting:NativeLighting(ambient:ambient,contrast:contrast,transform:lightingTransform)) : meshes
    }

    static func palette(_ packed: Int) -> SIMD4<Float> {
        let h = Float(packed >> 10)/64 + 1/128, s = Float((packed >> 7)&7)/8 + 1/16, l = Float(packed&127)/128
        let q = l < 0.5 ? l*(1+s) : l+s-l*s, p = 2*l-q
        func hue(_ input: Float) -> Float { let t = input-floor(input); return t < 1/6 ? p+(q-p)*6*t : t < 0.5 ? q : t < 2/3 ? p+(q-p)*(2/3-t)*6 : p }
        return SIMD4(hue(h+1/3),hue(h),hue(h-1/3),1)
    }
}


/// Original cache lighting profiles. Lighting is baked into the vertex colors;
/// the Metal, volume and portrait renderers consume the same shaded meshes.
struct NativeLighting: Sendable {
    var ambient: Int = 64
    var contrast: Int = 768
    var direction: SIMD3<Int> = SIMD3(-50,-10,-50)
    var transform: simd_float3x3 = matrix_identity_float3x3
    static let actor = NativeLighting(ambient:64,contrast:850,direction:SIMD3(-30,-50,-30))
    static let object = NativeLighting()
    static let portrait = NativeLighting()
}

enum NativeModelLighting {
    private enum VertexKey: Hashable {
        case source(Int,Int,Int)
        case local(Int,Int)
        case position(SIMD3<Int>)
    }
    private struct Normal {
        var sum = SIMD3<Int>.zero
        var count = 0
        mutating func add(_ value:SIMD3<Int>) {
            sum = SIMD3(sum.x+value.x,sum.y+value.y,sum.z+value.z)
            count += 1
        }
    }
    private struct Face {
        var mesh: Int
        var vertices: SIMD3<Int>
        var normal: SIMD3<Int>
        var color: Int
        var type: Int
    }

    /// Match Model.calculateNormals/light: restore cache coordinates and winding,
    /// accumulate only smooth faces, and retain flat-face and source-alpha rules.
    /// Coincident vertices merge only for an original multipart composition.
    static func shade(meshes:[NativeMesh],lighting:NativeLighting,mergeCoincidentVertices:Bool = false)->[NativeMesh] {
        var faces:[Face] = []
        var keys:[[VertexKey]] = Array(repeating:[],count:meshes.count)
        var normals:[VertexKey:Normal] = [:]
        for (mi,mesh) in meshes.enumerated() {
            let count = mesh.indices.count/3
            // Explicit-color terrain and overlays have no cache face metadata.
            guard mesh.indices.count%3 == 0,mesh.faceColors.count == count,mesh.faceRenderTypes.count == count else {continue}
            let points = mesh.vertices.map { vertex -> SIMD3<Int> in
                let p = lighting.transform * vertex.position * 128
                return SIMD3(Int(p.x.rounded(.toNearestOrEven)),-Int(p.y.rounded(.toNearestOrEven)),Int(p.z.rounded(.toNearestOrEven)))
            }
            keys[mi] = points.indices.map { index in
                if mergeCoincidentVertices {return .position(points[index])}
                if mesh.sourceVertices.count == mesh.vertices.count {return .source(mesh.sourceModel,mesh.slot,mesh.sourceVertices[index])}
                return .local(mi,index)
            }
            for f in 0..<count {
                // Mesh indices reverse the cache triangle after reflecting Y.
                // Mirrored meshes reverse the GPU winding too, so this also
                // preserves the mirrored original's outward normal.
                let v = SIMD3(Int(mesh.indices[f*3]),Int(mesh.indices[f*3+2]),Int(mesh.indices[f*3+1]))
                guard points.indices.contains(v.x),points.indices.contains(v.y),points.indices.contains(v.z) else {continue}
                let p = points[v.x],q = points[v.y],r = points[v.z]
                let ab = SIMD3(q.x-p.x,q.y-p.y,q.z-p.z),ac = SIMD3(r.x-p.x,r.y-p.y,r.z-p.z)
                var nx = ab.y*ac.z-ab.z*ac.y,ny = ab.z*ac.x-ab.x*ac.z,nz = ab.x*ac.y-ab.y*ac.x
                while abs(nx)>8192 || abs(ny)>8192 || abs(nz)>8192 {nx >>= 1;ny >>= 1;nz >>= 1}
                let length = max(1,Int(sqrt(Double(nx*nx+ny*ny+nz*nz))))
                let normal = SIMD3(nx*256/length,ny*256/length,nz*256/length)
                let type = mesh.faceRenderTypes[f]
                faces.append(Face(mesh:mi,vertices:v,normal:normal,color:mesh.faceColors[f],type:type))
                if type & 1 == 0 {
                    for index in [v.x,v.y,v.z] {normals[keys[mi][index],default:Normal()].add(normal)}
                }
            }
        }
        let d = lighting.direction
        let magnitude = Int(sqrt(Double(d.x*d.x+d.y*d.y+d.z*d.z)))
        let scale = max(1,(lighting.contrast*magnitude)>>8)
        var output = meshes
        for face in faces {
            for index in [face.vertices.x,face.vertices.y,face.vertices.z] {
                let smooth = normals[keys[face.mesh][index],default:Normal()]
                let flat = face.type & 1 != 0
                let n = flat ? face.normal : smooth.sum
                let divisor = flat ? scale+scale/2 : scale*max(1,smooth.count)
                let light = lighting.ambient+(d.x*n.x+d.y*n.y+d.z*n.z)/divisor
                var color:SIMD4<Float>
                if face.type & 2 != 0 {
                    // Original getTexLight returns 127-light. Pix3D selects one
                    // of four texture banks (1,7/8,3/4,5/8), then shifts by 0/1.
                    let shade = 127-max(0,min(127,light))
                    let intensity = (1-Float((shade>>4)&3)/8)/Float(1<<(shade>>6))
                    color = SIMD4(intensity,intensity,intensity,1)
                } else {
                    color = NativeModel.palette((face.color & 0xff80)+max(2,min(126,(light*(face.color & 127))>>7)))
                }
                color.w = output[face.mesh].vertices[index].color.w
                output[face.mesh].vertices[index].color = color
            }
        }
        return output
    }
}
