import Foundation
import CoreGraphics
import ImageIO
import simd
#if canImport(UIKit)
import UIKit
#endif

/// Original cache chat heads, including their UVs, palette alpha and keyed textures.
/// The software painter is capped at 112 pixels on its longest side for animated UI use.
@MainActor enum NativePortraitRenderer {
    #if canImport(UIKit)
    static func image(head: [String:Any], store: NativeAssetStore, time: Double = 0, size: CGSize = CGSize(width:256,height:256)) async throws -> UIImage {
        UIImage(cgImage: try await cgImage(head:head,store:store,time:time,size:size))
    }
    #endif

    static func cgImage(head: [String:Any], store: NativeAssetStore, time: Double = 0, size: CGSize = CGSize(width:112,height:112)) async throws -> CGImage {
        let data = try JSONSerialization.data(withJSONObject:head["parts"] as? [[String:Any]] ?? [])
        let parts = try JSONDecoder().decode([NativeAssetPart].self,from:data)
        guard parts.count <= 64 else { throw NativeAssetError.malformed("portrait part budget") }
        var meshes = try await NativeComposition.meshes(parts:parts,store:store,lighting:nil)
        if let sequenceID = head["sequence"] as? Int, sequenceID >= 0, let sequence = try? await store.sequence(sequenceID) {
            meshes = NativeAnimator.pose(meshes:meshes,sequence:sequence,time:time)
        }
        // Interface models are lit after their speaking pose, before the UI
        // camera's pitch/yaw, with shared normals across matching body parts.
        meshes=NativeModelLighting.shade(meshes:meshes,lighting:.portrait,mergeCoincidentVertices:true)
        var textures:[Int:Data] = [:]
        let textureIDs = Set(meshes.map(\.textureID).filter { $0 >= 0 })
        guard textureIDs.count <= 16 else { throw NativeAssetError.malformed("portrait texture budget") }
        for id in textureIDs { try Task.checkCancellation(); textures[id] = try await store.texture(id) }
        return try rasterize(meshes:meshes,textureData:textures,
                             pitch:Float(head["xan"] as? Int ?? 0) * .pi/1024,
                             yaw:Float(head["yan"] as? Int ?? 0) * .pi/1024,
                             zoom:Float(head["zoom"] as? Int ?? 550),size:size)
    }

    private struct Texture {
        let width:Int, height:Int
        var pixels:[SIMD4<Float>]
        init(data:Data) throws {
            guard let source = CGImageSourceCreateWithData(data as CFData,nil),
                  let image = CGImageSourceCreateImageAtIndex(source,0,nil),
                  image.width > 0, image.height > 0, image.width <= 256, image.height <= 256 else {
                throw NativeAssetError.malformed("portrait texture dimensions")
            }
            width = image.width; height = image.height
            var rgba = [UInt8](repeating:0,count:width*height*4)
            let bitmap = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
            guard let context = CGContext(data:&rgba,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:bitmap) else { throw NativeAssetError.malformed("portrait texture buffer") }
            // Match the world renderer's decoded PNG orientation. UVs are used without a flip.
            context.draw(image,in:CGRect(x:0,y:0,width:width,height:height))
            pixels = []
            pixels.reserveCapacity(width*height)
            for i in stride(from:0,to:rgba.count,by:4) {
                // The original importer keys palette index zero (magenta) before filtering.
                if rgba[i] == 255 && rgba[i+1] == 0 && rgba[i+2] == 255 { pixels.append(.zero) }
                else { pixels.append(SIMD4(Float(rgba[i]),Float(rgba[i+1]),Float(rgba[i+2]),Float(rgba[i+3]))/255) }
            }
        }
        func sample(_ uv:SIMD2<Float>) -> SIMD4<Float> {
            guard uv.x.isFinite, uv.y.isFinite else { return .zero }
            let x = (uv.x-floor(uv.x))*Float(width)-0.5
            let y = (uv.y-floor(uv.y))*Float(height)-0.5
            let ix = Int(floor(x)), iy = Int(floor(y)), fx = x-floor(x), fy = y-floor(y)
            func texel(_ x:Int,_ y:Int) -> SIMD4<Float> { pixels[((y % height + height) % height)*width + (x % width + width) % width] }
            return (texel(ix,iy)*(1-fx)+texel(ix+1,iy)*fx)*(1-fy) + (texel(ix,iy+1)*(1-fx)+texel(ix+1,iy+1)*fx)*fy
        }
    }

    /// Kept independent of UIKit so the exact portrait path can be exercised by native checks.
    static func rasterize(meshes original:[NativeMesh],textureData:[Int:Data],pitch:Float = 0,yaw:Float = 0,zoom:Float = 550,size:CGSize = CGSize(width:112,height:112)) throws -> CGImage {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0,
              pitch.isFinite, yaw.isFinite, zoom.isFinite,
              original.reduce(0,{$0+$1.indices.count/3}) <= 20_000,
              original.contains(where: { !$0.vertices.isEmpty }) else { throw NativeAssetError.malformed("portrait geometry or size") }
        let ratio = min(1,112/max(size.width,size.height))
        let width = max(1,Int((size.width*ratio).rounded())), height = max(1,Int((size.height*ratio).rounded()))
        var textures:[Int:Texture] = [:]
        guard textureData.count <= 16 else { throw NativeAssetError.malformed("portrait texture budget") }
        for (id,data) in textureData { textures[id] = try Texture(data:data) }
        var meshes = original
        var low = SIMD3<Float>(repeating:.greatestFiniteMagnitude), high = SIMD3<Float>(repeating:-.greatestFiniteMagnitude)
        let cy = cos(yaw), sy = sin(yaw), cx = cos(pitch), sx = sin(pitch)
        for m in meshes.indices { for i in meshes[m].vertices.indices {
            let p = meshes[m].vertices[i].position
            let r = SIMD3(cy*p.x+sy*p.z,p.y,cy*p.z-sy*p.x)
            let v = SIMD3(r.x,cx*r.y+sx*r.z,cx*r.z-sx*r.y)
            guard v.x.isFinite, v.y.isFinite, v.z.isFinite else { throw NativeAssetError.malformed("portrait coordinates") }
            meshes[m].vertices[i].position = v; low = simd_min(low,v); high = simd_max(high,v)
        } }
        let center = (low+high)/2
        let extent = max(0.01,max(high.x-low.x,high.y-low.y))
        let factor = Float(min(width,height))*0.78/extent * max(0.65,min(1.15,zoom/550))
        struct Triangle { var vertices:[NativeVertex]; var points:[SIMD2<Float>]; var texture:Int; var depth:Float; var priority:Int; var order:Int }
        var triangles:[Triangle] = []
        func point(_ p:SIMD3<Float>) -> SIMD2<Float> { SIMD2((p.x-center.x)*factor+Float(width)/2,Float(height)/2-(p.y-center.y)*factor) }
        for mesh in meshes { for f in 0..<mesh.indices.count/3 {
            let indices = Array(mesh.indices[(f*3)..<(f*3+3)]).map(Int.init)
            guard indices.allSatisfy({mesh.vertices.indices.contains($0)}) else { throw NativeAssetError.malformed("portrait triangle index") }
            let v = indices.map { mesh.vertices[$0] }
            if v.allSatisfy({$0.color.w <= 0}) { continue }
            if mesh.textureID >= 0 && textures[mesh.textureID] == nil { throw NativeAssetError.missing("portrait texture \(mesh.textureID)") }
            triangles.append(Triangle(vertices:v,points:v.map { point($0.position) },texture:mesh.textureID,depth:(v[0].position.z+v[1].position.z+v[2].position.z)/3,priority:f < mesh.priorities.count ? mesh.priorities[f] : 0,order:triangles.count))
        } }
        triangles.sort {
            if $0.depth != $1.depth { return $0.depth > $1.depth }
            if $0.priority != $1.priority { return $0.priority < $1.priority }
            return $0.order < $1.order
        }
        var pixels = [SIMD4<Float>](repeating:.zero,count:width*height)
        func edge(_ a:SIMD2<Float>,_ b:SIMD2<Float>,_ p:SIMD2<Float>) -> Float { (b.x-a.x)*(p.y-a.y)-(b.y-a.y)*(p.x-a.x) }
        for triangle in triangles {
            try Task.checkCancellation()
            let a = triangle.points[0], b = triangle.points[1], c = triangle.points[2]
            let area = edge(a,b,c)
            if abs(area) < 0.00001 { continue }
            let x0 = max(0,Int(floor(min(a.x,min(b.x,c.x))))), x1 = min(width-1,Int(ceil(max(a.x,max(b.x,c.x)))))
            let y0 = max(0,Int(floor(min(a.y,min(b.y,c.y))))), y1 = min(height-1,Int(ceil(max(a.y,max(b.y,c.y)))))
            if x0 > x1 || y0 > y1 { continue }
            let v = triangle.vertices, texture = textures[triangle.texture]
            for y in y0...y1 { for x in x0...x1 {
                let p = SIMD2(Float(x)+0.5,Float(y)+0.5)
                let weights = SIMD3(edge(b,c,p)/area,edge(c,a,p)/area,edge(a,b,p)/area)
                if weights.x < 0 || weights.y < 0 || weights.z < 0 { continue }
                let color = simd_clamp(v[0].color*weights.x+v[1].color*weights.y+v[2].color*weights.z,SIMD4(repeating:0),SIMD4(repeating:1))
                var source = SIMD4(color.x*color.w,color.y*color.w,color.z*color.w,color.w)
                if let texture {
                    let uv = v[0].uv*weights.x+v[1].uv*weights.y+v[2].uv*weights.z
                    source *= texture.sample(uv)
                }
                // Match the game's alpha-test threshold, then composite premultiplied RGBA.
                if source.w < 0.2 { continue }
                let index = y*width+x
                pixels[index] = source + pixels[index]*(1-source.w)
            } }
        }
        var rgba = [UInt8](); rgba.reserveCapacity(width*height*4)
        for p in pixels { for value in [p.x,p.y,p.z,p.w] { rgba.append(UInt8(max(0,min(255,(value*255).rounded())))) } }
        let bitmap = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let provider = CGDataProvider(data:Data(rgba) as CFData),
              let image = CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:bitmap),provider:provider,decode:nil,shouldInterpolate:true,intent:.defaultIntent) else { throw NativeAssetError.malformed("portrait image buffer") }
        return image
    }
}
