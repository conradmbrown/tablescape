import Foundation
import simd

struct NativeAssetPart: Codable, Sendable {
    var models: [Int]
    var recolS: [Int]?
    var recolD: [Int]?
    var slot: Int?
    var offsetY: Float?
    var yaw: Float?
    var modelOffsetX: Float?
    var modelOffsetZ: Float?
    var mirror: Bool?
}
struct NativeTransform: Codable, Sendable { var type: Int; var x: Int; var y: Int; var z: Int; var labels: [Int] }
struct NativeFrame: Codable, Sendable { var delay: Int; var transforms: [NativeTransform] }
struct NativeSequence: Codable, Sendable {
    var id: Int
    var loops: Int?
    var maxloops: Int?
    var duplicatebehaviour: Int?
    var postanim_move: Int?
    var replaceheldleft: Int?
    var replaceheldright: Int?
    var leftMale: NativeAssetPart?
    var leftFemale: NativeAssetPart?
    var rightMale: NativeAssetPart?
    var rightFemale: NativeAssetPart?
    var frames: [NativeFrame]
    var byteCount: Int { frames.reduce(0) { $0 + 32 + $1.transforms.reduce(0) { $0 + 48 + $1.labels.count * 8 } } }
    var duration: Double { Double(frames.reduce(0) { $0 + max(1,$1.delay) }) / 50 }
    var actionDuration: Double {
        let tail = max(0,min(frames.count,loops ?? 0))
        return duration + Double(frames.suffix(tail).reduce(0) { $0 + max(1,$1.delay) } * max(0,(maxloops ?? 1)-1)) / 50
    }
}

enum NativeAnimator {
    /// Cache and sequence labels are bytes; an unlabeled render vertex uses -1.
    /// Keep membership on the stack instead of hashing every visited vertex.
    private struct LabelMask {
        var words = SIMD4<UInt64>(repeating:0)
        init(_ labels:[Int]) {
            for label in labels where UInt(bitPattern:label) < 256 {
                words[label >> 6] |= UInt64(1) << (label & 63)
            }
        }
        @inline(__always) func contains(_ label:Int) -> Bool {
            guard UInt(bitPattern:label) < 256 else { return false }
            return words[label >> 6] & (UInt64(1) << (label & 63)) != 0
        }
    }

    struct Cursor: Sendable { var index: Int; var next: Int; var fraction: Float; var finished: Bool }
    static func cursor(sequence: NativeSequence, time: Double, loop: Bool = true) -> Cursor {
        let frames = sequence.frames
        guard !frames.isEmpty else { return Cursor(index:0,next:0,fraction:0,finished:true) }
        let extra = loop ? 1 : 0
        let total = frames.reduce(0) { $0 + max(1,$1.delay) + extra }
        let cycle = max(0,time) * 50
        var tick = Int(min(cycle,Double(Int.max/2)))
        let tailCount = max(0,min(frames.count,sequence.loops ?? 0))
        let tail = frames.suffix(tailCount).reduce(0) { $0 + max(1,$1.delay) }
        let maximum = total + tail * max(0,(sequence.maxloops ?? 1)-1)
        let finished = !loop && tick >= maximum
        if loop { tick %= max(1,total) }
        else if tick >= total { tick = tail > 0 && !finished ? total-tail+(tick-total)%tail : total-1 }
        var index = 0
        while index < frames.count-1 && tick >= max(1,frames[index].delay)+extra { tick -= max(1,frames[index].delay)+extra; index += 1 }
        var next = index+1
        if next == frames.count { next = loop ? 0 : tailCount > 0 && !finished ? frames.count-tailCount : index }
        let fraction = finished ? 0 : min(1,(Float(tick)+Float(cycle-floor(cycle)))/Float(max(1,frames[index].delay)+extra))
        return Cursor(index:index,next:next,fraction:fraction,finished:finished)
    }

    /// CPU reference implementation matching the original transform order, including shared pivots.
    static func pose(meshes: [NativeMesh], sequence: NativeSequence, time: Double, loop: Bool = true) -> [NativeMesh] {
        guard !sequence.frames.isEmpty else { return meshes }
        let c = cursor(sequence:sequence,time:time,loop:loop)
        var current = apply(meshes:meshes,frame:sequence.frames[c.index])
        if c.next == c.index || c.fraction == 0 { return current }
        let next = apply(meshes:meshes,frame:sequence.frames[c.next])
        for m in current.indices { for i in current[m].vertices.indices {
            current[m].vertices[i].position = simd_mix(current[m].vertices[i].position,next[m].vertices[i].position,SIMD3<Float>(repeating:c.fraction))
            current[m].vertices[i].color.w += (next[m].vertices[i].color.w-current[m].vertices[i].color.w)*c.fraction
        } }
        return current
    }

    static func apply(meshes: [NativeMesh], frame: NativeFrame) -> [NativeMesh] {
        var work = meshes
        for m in work.indices { for i in work[m].vertices.indices { work[m].vertices[i].position *= SIMD3<Float>(128,-128,128) } }
        var origin = SIMD3<Float>.zero
        for transform in frame.transforms {
            let labels = LabelMask(transform.labels), delta = SIMD3(Float(transform.x),Float(transform.y),Float(transform.z))
            if transform.type == 0 {
                var unique = Set<SIMD3<Float>>(), sum = SIMD3<Float>.zero
                for mesh in work { for i in mesh.vertices.indices where i < mesh.vertexLabels.count && labels.contains(mesh.vertexLabels[i]) {
                    let vertex = mesh.vertices[i].position
                    if unique.insert(vertex).inserted { sum += vertex }
                } }
                origin = (unique.isEmpty ? .zero : sum/Float(unique.count)) + delta
                continue
            }
            if transform.type == 5 {
                let alphaDelta = Float(transform.x*8)/255
                for m in work.indices { for i in work[m].vertices.indices {
                    if i < work[m].faceLabels.count && labels.contains(work[m].faceLabels[i]) {
                        work[m].vertices[i].color.w = max(0,min(1,work[m].vertices[i].color.w-alphaDelta))
                    }
                } }
                continue
            }
            // All vertices selected by a transform share its rotation and scale.
            var cx:Float = 1, sx:Float = 0, cy:Float = 1, sy:Float = 0, cz:Float = 1, sz:Float = 0
            if transform.type == 2 {
                let ax = Float(transform.x & 255) * .pi/128
                let ay = Float(transform.y & 255) * .pi/128
                let az = Float(transform.z & 255) * .pi/128
                cx = cos(ax); sx = sin(ax); cy = cos(ay); sy = sin(ay); cz = cos(az); sz = sin(az)
            }
            let scale = delta/128
            for m in work.indices { for i in work[m].vertices.indices {
                guard i < work[m].vertexLabels.count, labels.contains(work[m].vertexLabels[i]) else { continue }
                var v = work[m].vertices[i].position
                switch transform.type {
                case 1: v += delta
                case 3: v = (v-origin)*scale+origin
                case 2:
                    v -= origin
                    v = SIMD3(v.y*sz+v.x*cz,v.y*cz-v.x*sz,v.z)
                    v = SIMD3(v.x,v.y*cx-v.z*sx,v.y*sx+v.z*cx)
                    v = SIMD3(v.z*sy+v.x*cy,v.y,v.z*cy-v.x*sy)
                    v += origin
                default: break
                }
                work[m].vertices[i].position = v
            } }
        }
        for m in work.indices { for i in work[m].vertices.indices { work[m].vertices[i].position /= SIMD3<Float>(128,-128,128) } }
        return work
    }

    static func replacementParts(_ original: [NativeAssetPart], sequence: NativeSequence?, gender: Int) -> [NativeAssetPart] {
        guard let sequence else { return original }
        var parts = original.filter {
            !($0.slot == 3 && (sequence.replaceheldright ?? -1) >= 0) && !($0.slot == 5 && (sequence.replaceheldleft ?? -1) >= 0)
        }
        func appendBodyColours(_ originalPart: NativeAssetPart, slot: Int) -> NativeAssetPart {
            var part = originalPart; part.slot = slot
            if let body = original.first, let source = body.recolS, let destination = body.recolD, source.count >= 5, destination.count >= source.count {
                part.recolS = (part.recolS ?? []) + source.suffix(5)
                part.recolD = (part.recolD ?? []) + destination.suffix(5)
            }
            return part
        }
        if (sequence.replaceheldleft ?? -1) >= 512, let part = gender == 0 ? sequence.leftMale : sequence.leftFemale { parts.append(appendBodyColours(part,slot:5)) }
        if (sequence.replaceheldright ?? -1) >= 512, let part = gender == 0 ? sequence.rightMale : sequence.rightFemale { parts.append(appendBodyColours(part,slot:3)) }
        return parts
    }
}

// Keep scenery's public profile name for callers while sharing the same model light.
typealias NativeSceneryLighting = NativeLighting

enum NativeComposition {
    static func sceneryLighting(actor: [String:Any]) -> NativeLighting {
        func number(_ key:String,_ fallback:Float) -> Float { (actor[key] as? NSNumber)?.floatValue ?? fallback }
        let sx = number("scaleX",1), sy = number("scaleY",1), sz = number("scaleZ",sx)
        let scale = SIMD3(sx > 0 ? sx : 1, sy > 0 ? sy : 1, sz > 0 ? sz : 1)
        let yaw = number("angle",0) * .pi/2 + ((actor["shape"] as? Int ?? 0) == 11 ? .pi/4 : 0)
        let rotation = simd_float3x3(simd_quatf(angle:yaw,axis:SIMD3(0,1,0)))
        return NativeLighting(ambient:Int(number("lightAmbient",64)),contrast:Int(number("lightContrast",768)),transform:rotation * simd_float3x3(diagonal:scale))
    }
    static func actorLighting(actor: [String:Any], kind: String) -> NativeLighting {
        let object = kind == "obj"
        var lighting: NativeLighting = object ? .object : .actor
        let offsets = kind == "npc" ? NativeDefinitionLighting.npc(type: (actor["type"] as? NSNumber)?.intValue ?? -1) : .zero
        lighting.ambient = (actor["lightAmbient"] as? NSNumber)?.intValue ?? (lighting.ambient + offsets.x)
        lighting.contrast = (actor["lightContrast"] as? NSNumber)?.intValue ?? (lighting.contrast + offsets.y)
        // Item definitions resize the model before lighting. NPC/player resizing
        // follows cached base-pose lighting in the original client.
        if object {
            let x = (actor["scaleX"] as? NSNumber)?.floatValue ?? 1
            let y = (actor["scaleY"] as? NSNumber)?.floatValue ?? 1
            let z = (actor["scaleZ"] as? NSNumber)?.floatValue ?? x
            lighting.transform = simd_float3x3(diagonal: SIMD3(x,y,z))
        }
        return lighting
    }
    static func meshes(parts: [[String:Any]], store: NativeAssetStore, lighting: NativeLighting? = .actor) async throws -> [NativeMesh] {
        let bytes = try JSONSerialization.data(withJSONObject:parts)
        return try await meshes(parts:JSONDecoder().decode([NativeAssetPart].self,from:bytes),store:store,lighting:lighting)
    }
    static func meshes(parts: [NativeAssetPart], store: NativeAssetStore, lighting: NativeLighting? = .actor) async throws -> [NativeMesh] {
        var result: [NativeMesh] = []
        var modelCount = 0
        for part in parts {
            let pairs = zip(part.recolS ?? [],part.recolD ?? []).map { SIMD2($0.0,$0.1) }
            let angle = (part.yaw ?? 0) * .pi/180, c = cos(angle), s = sin(angle)
            for id in part.models where id >= 0 && id < 65535 {
                let model = try await store.model(id)
                var meshes = model.mesh(recolorPairs:pairs,mirrored:part.mirror ?? false,lit:false)
                modelCount += 1
                for m in meshes.indices {
                    meshes[m].slot = part.slot ?? -1
                    for i in meshes[m].vertices.indices {
                        let p = meshes[m].vertices[i].position
                        meshes[m].vertices[i].position = SIMD3(c*p.x+s*p.z+(part.modelOffsetX ?? 0),p.y-(part.offsetY ?? 0),c*p.z-s*p.x+(part.modelOffsetZ ?? 0))
                    }
                }
                result.append(contentsOf:meshes)
            }
        }
        // Original combined models share normals across coincident part seams.
        // Light once after local assembly; keep the result cached before animation.
        if let lighting {
            result = NativeModelLighting.shade(meshes: result, lighting: lighting, mergeCoincidentVertices: modelCount > 1)
        }
        return result
    }

    /// Applies scenery's scale, local yaw and hill skew. Caller adds the world-space tile center.
    static func applyScenery(meshes: [NativeMesh], actor: [String:Any]) -> [NativeMesh] {
        func number(_ name:String,_ fallback:Float = 0) -> Float { (actor[name] as? NSNumber)?.floatValue ?? fallback }
        let sx = number("scaleX",1), sy = number("scaleY",1), sz = number("scaleZ",sx)
        let scale = SIMD3(sx > 0 ? sx : 1,sy > 0 ? sy : 1,sz > 0 ? sz : 1)
        let shape = actor["shape"] as? Int ?? 0, angle = number("angle") * .pi/2
        let yaw = angle + (shape == 11 ? .pi/4 : 0), c = cos(yaw), s = sin(yaw)
        let heights = actor["hillHeights"] as? [Int] ?? []
        let offsetX = number("offsetX"), offsetZ = number("offsetZ")
        var output = meshes
        for m in output.indices { for i in output[m].vertices.indices {
            let p = output[m].vertices[i].position * scale
            var v = SIMD3(c*p.x+s*p.z,p.y,c*p.z-s*p.x)
            if heights.count == 4 {
                let average = heights.reduce(0,+)/4
                let h = shape == 11 ? SIMD3(cos(-Float.pi/4)*v.x+sin(-Float.pi/4)*v.z,v.y,cos(-Float.pi/4)*v.z-sin(-Float.pi/4)*v.x) : v
                let x = Int(((h.x+offsetX)*128).rounded()), z = Int(((h.z+offsetZ)*128).rounded())
                let south = heights[0]+(heights[1]-heights[0])*(x+64)/128
                let north = heights[3]+(heights[2]-heights[3])*(x+64)/128
                let height = south+(north-south)*(z+64)/128
                v.y += Float(average-height)/128
            }
            output[m].vertices[i].position = v
        } }
        return output
    }
}
