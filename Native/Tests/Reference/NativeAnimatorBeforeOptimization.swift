// Frozen test-only reference captured from Assets/NativeAnimation.swift on 2026-09-27,
// immediately before the label-mask/transform-constant optimization. The original
// NativeAnimator enum is unchanged except for its name and standalone imports.
// Captured complete source SHA256: 7ed0d8059a397a7bc56f9a0bce635928a7a1bd0893445d991fc6cca87c16e8bd
// Do not update this reference to match a new implementation; preserve it as the oracle.
import Foundation
import simd

enum NativeAnimatorBeforeOptimization {
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
            let labels = Set(transform.labels), delta = SIMD3(Float(transform.x),Float(transform.y),Float(transform.z))
            if transform.type == 0 {
                var unique = Set<SIMD3<Float>>(), sum = SIMD3<Float>.zero
                for mesh in work { for i in mesh.vertices.indices where i < mesh.vertexLabels.count && labels.contains(mesh.vertexLabels[i]) {
                    let vertex = mesh.vertices[i].position
                    if unique.insert(vertex).inserted { sum += vertex }
                } }
                origin = (unique.isEmpty ? .zero : sum/Float(unique.count)) + delta
                continue
            }
            for m in work.indices { for i in work[m].vertices.indices {
                if transform.type == 5 {
                    if i < work[m].faceLabels.count && labels.contains(work[m].faceLabels[i]) {
                        work[m].vertices[i].color.w = max(0,min(1,work[m].vertices[i].color.w-Float(transform.x*8)/255))
                    }
                    continue
                }
                guard i < work[m].vertexLabels.count, labels.contains(work[m].vertexLabels[i]) else { continue }
                var v = work[m].vertices[i].position
                switch transform.type {
                case 1: v += delta
                case 3: v = (v-origin)*(delta/128)+origin
                case 2:
                    v -= origin
                    var angle = Float(transform.z & 255) * .pi/128, c = cos(angle), s = sin(angle)
                    v = SIMD3(v.y*s+v.x*c,v.y*c-v.x*s,v.z)
                    angle = Float(transform.x & 255) * .pi/128; c = cos(angle); s = sin(angle)
                    v = SIMD3(v.x,v.y*c-v.z*s,v.y*s+v.z*c)
                    angle = Float(transform.y & 255) * .pi/128; c = cos(angle); s = sin(angle)
                    v = SIMD3(v.z*s+v.x*c,v.y,v.z*c-v.x*s)
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
