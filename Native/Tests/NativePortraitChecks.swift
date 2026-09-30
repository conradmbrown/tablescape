import Foundation
import CoreGraphics
import ImageIO
import simd
/// Exercises the application's shared CoreGraphics/ImageIO renderer directly on macOS.
/// UIKit wrapping and visionOS presentation are covered by the app build/simulator separately.
@main struct NativePortraitChecks {
    @MainActor static func main() async throws {
        precondition(CommandLine.arguments.count == 3, "Expected repository and render-check output directories")
        let root=URL(fileURLWithPath:CommandLine.arguments[1]),out=URL(fileURLWithPath:CommandLine.arguments[2]).appendingPathComponent("Artifacts")
        try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
        let pack=root.appendingPathComponent("Native/TableScape/Resources/AssetPack")
        func png(_ image:CGImage)->Data {
            let data=NSMutableData();let destination=CGImageDestinationCreateWithData(data,"public.png" as CFString,1,nil)!
            CGImageDestinationAddImage(destination,image,nil);precondition(CGImageDestinationFinalize(destination));return data as Data
        }
        func bytes(_ image:CGImage)->[UInt8] { Array(image.dataProvider!.data! as Data) }
        func visible(_ image:CGImage)->Int { let p=bytes(image);return stride(from:3,to:p.count,by:4).filter {p[$0]>0}.count }
        // Analytic 2x2 texture tests filtering, source alpha, UV repeat and the original magenta key.
        let rgba:[UInt8]=[255,0,0,255, 0,255,0,255, 0,0,128,128, 255,0,255,255]
        let provider=CGDataProvider(data:Data(rgba) as CFData)!
        let bitmap=CGBitmapInfo.byteOrder32Big.rawValue|CGImageAlphaInfo.premultipliedLast.rawValue
        let texture=CGImage(width:2,height:2,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:8,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:bitmap),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
        let data=png(texture)
        func quad(_ uv:SIMD2<Float>,alpha:Float=1)->NativeMesh {
            let positions:[SIMD3<Float>]=[SIMD3(-1,-1,0),SIMD3(1,-1,0),SIMD3(1,1,0),SIMD3(-1,1,0)]
            return NativeMesh(vertices:positions.map {NativeVertex(position:$0,color:SIMD4(1,1,1,alpha),uv:uv)},indices:[0,1,2,0,2,3],textureID:0)
        }
        var colors=Set<[UInt8]>(),transparent=0
        for y:Float in [0.25,0.75] { for x:Float in [0.25,0.75] {
            let first=try NativePortraitRenderer.rasterize(meshes:[quad(SIMD2(x,y))],textureData:[0:data])
            let repeated=try NativePortraitRenderer.rasterize(meshes:[quad(SIMD2(x+2,y-3))],textureData:[0:data])
            precondition(bytes(first)==bytes(repeated),"UV repeat changed sample")
            let p=bytes(first),offset=(56*112+61)*4
            colors.insert(Array(p[offset..<(offset+4)]))
            if visible(first)==0 { transparent += 1 }
        } }
        precondition(transparent==1 && colors.count==4,"Keyed transparency or distinct UV samples missing")
        precondition(colors.contains([0,0,128,128]),"Original PNG alpha was lost")
        let bilinear=try NativePortraitRenderer.rasterize(meshes:[quad(SIMD2(0.5,0.5))],textureData:[0:data])
        let filtered=bytes(bilinear),sample=(56*112+61)*4
        precondition(Array(filtered[sample..<(sample+4)]) == [64,64,32,160],"Premultiplied bilinear filtering changed")
        let alpha=try NativePortraitRenderer.rasterize(meshes:[quad(SIMD2(0.25,0.25),alpha:0.1)],textureData:[0:data])
        precondition(visible(alpha)==0,"Vertex alpha-test did not discard")
        var varying=quad(.zero)
        for i in varying.vertices.indices { varying.vertices[i].uv=SIMD2((varying.vertices[i].position.x+1)/2,(varying.vertices[i].position.y+1)/2) }
        let fixture=try NativePortraitRenderer.rasterize(meshes:[varying],textureData:[0:data],size:CGSize(width:4096,height:2048))
        precondition(fixture.width==112 && fixture.height==56,"Software portrait bound failed")
        try png(fixture).write(to:out.appendingPathComponent("portrait-texture-fixture.png"))
        let store=NativeAssetStore(fetch:{_ in throw NativeAssetError.missing("offline fixture")},packURL:pack,cacheURL:out.appendingPathComponent("PortraitCache"))
        // Fixed original textured cache IDs make fixture coverage independent of directory order.
        for id in [1003,1004,1005] {
            let model=try await store.model(id)
            precondition(model.renderTypes.contains(where:{$0 & 2 != 0}),"Expected original textured model")
            let head:[String:Any]=["parts":[["models":[id]]],"xan":150,"yan":100,"zoom":550]
            let image=try await NativePortraitRenderer.cgImage(head:head,store:store,size:CGSize(width:192,height:236))
            precondition(visible(image)>40,"Original textured cache model not visible")
            let rawMeshes=try await NativeComposition.meshes(parts:[["models":[id]]],store:store,lighting:nil)
            var rawTextures:[Int:Data]=[:]
            for textureID in Set(rawMeshes.map(\.textureID).filter {$0>=0}) {rawTextures[textureID]=try await store.texture(textureID)}
            let unlit=try NativePortraitRenderer.rasterize(meshes:rawMeshes,textureData:rawTextures,
                pitch:150 * .pi/1024,yaw:100 * .pi/1024,zoom:550,size:CGSize(width:192,height:236))
            precondition(bytes(image) != bytes(unlit),"Portrait consumer left original textured model unlit")
            precondition(visible(image)==visible(unlit),"Portrait lighting changed geometry or alpha silhouette")
            try png(image).write(to:out.appendingPathComponent("portrait-original-model-\(id).png"))
            print("Original textured model \(id): visiblePixels=\(visible(image)) resolution=\(image.width)x\(image.height)")
        }
        print("PASS exact native portrait path: original textured geometry, original UVs, repeat/bilinear filtering, original PNG alpha, magenta key, vertex alpha discard, and 112px bound")
    }
}
