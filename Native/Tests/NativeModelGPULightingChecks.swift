import Foundation
import RealityKit
import AppKit
import Metal
import ImageIO
import simd

/// Close-up original models through the shipped MaterialX graph and vertex layout.
/// This is actual macOS RealityKit GPU evidence, not headset visual acceptance.
@main struct NativeModelGPULightingChecks {
    @MainActor static func main() {
        _ = NSApplication.shared
        let bootstrap = ARView(frame:.zero)
        Task { @MainActor in
            do {try await run();_ = bootstrap;exit(0)}
            catch {print("FAIL model GPU lighting: \(error)");exit(1)}
        }
        RunLoop.main.run()
    }
    static func require(_ condition:Bool,_ message:String) {
        if !condition {print("FAIL model GPU lighting: \(message)");fflush(stdout);exit(1)}
    }
    @MainActor private final class FramePump {
        let renderer: RealityRenderer
        let output: RealityRenderer.CameraOutput
        init(renderer:RealityRenderer,output:RealityRenderer.CameraOutput) {self.renderer=renderer;self.output=output}
        func render() async throws {
            try await withCheckedThrowingContinuation { (continuation:CheckedContinuation<Void,Error>) in
                do {try renderer.updateAndRender(deltaTime:1.0/60,cameraOutput:output,onComplete:{_ in continuation.resume()})}
                catch {continuation.resume(throwing:error)}
            }
        }
    }
    @MainActor static func run() async throws {
        require(CommandLine.arguments.count==3,"Expected source and build paths")
        let source=URL(fileURLWithPath:CommandLine.arguments[1])
        let build=URL(fileURLWithPath:CommandLine.arguments[2])
        let artifacts=build.appendingPathComponent("Artifacts")
        let store=NativeAssetStore(fetch:{_ in throw NativeAssetError.missing("offline model GPU check")},
            packURL:source.appendingPathComponent("Native/TableScape/Resources/AssetPack"),cacheURL:build.appendingPathComponent("UnusedCache"))
        let renderer=try RealityRenderer(),device=MTLCreateSystemDefaultDevice()!
        let size=512
        let descriptor=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba8Unorm,width:size,height:size,mipmapped:false)
        descriptor.usage=[.renderTarget,.shaderRead];descriptor.storageMode = .shared
        let target=device.makeTexture(descriptor:descriptor)!
        let output=try RealityRenderer.CameraOutput(.singleProjection(colorTexture:target))
        let framePump=FramePump(renderer:renderer,output:output)
        let camera=PerspectiveCamera();camera.position=[0,0,4]
        renderer.entities.append(camera);renderer.activeCamera=camera
        renderer.cameraSettings.colorBackground = .color(CGColor(red:0.11,green:0.02,blue:0.17,alpha:1))
        renderer.cameraSettings.isToneMappingEnabled=false
        let graph=try await ShaderGraphMaterial(named:VolumeMaterialSource.name,from:VolumeMaterialSource.data())
        var textures:[Int:TextureResource]=[:]
        let white=try await TextureResource(image:VolumeTextureImage.decode(nil),options:.init(semantic:.raw))
        let content=Entity();renderer.entities.append(content)
        var completedFrames=0
        var reports:[[String:Any]]=[]

        @MainActor func material(_ id:Int) async throws -> ShaderGraphMaterial {
            var value=graph;value.faceCulling = .none
            try value.setParameter(name:"gameCenter",value:.simd3Float(.zero))
            try value.setParameter(name:"boardScale",value:.float(1))
            try value.setParameter(name:"clipEnabled",value:.float(0))
            try value.setParameter(name:"alphaThreshold",value:.float(0.2))
            for i in 0..<8 {try value.setParameter(name:"edge\(i)",value:.simd3Float([0,0,1]))}
            var texture=white
            if id>=0 {
                if let cached=textures[id] {texture=cached}
                else {
                    texture=try await TextureResource(image:VolumeTextureImage.decode(try await store.texture(id)),options:.init(semantic:.raw))
                    textures[id]=texture
                }
            }
            try value.setParameter(name:"gameTexture",value:.textureResource(texture))
            return value
        }
        @MainActor func upload(_ meshes:[NativeMesh]) async throws {
            for child in Array(content.children) {child.removeFromParent()}
            for mesh in meshes where !mesh.vertices.isEmpty && !mesh.indices.isEmpty {
                var descriptor=LowLevelMesh.Descriptor(vertexCapacity:mesh.vertices.count,indexCapacity:mesh.indices.count)
                descriptor.vertexAttributes=[
                    .init(semantic:.position,format:.float3,offset:MemoryLayout<NativeVertex>.offset(of:\.position)!),
                    .init(semantic:.color,format:.float4,offset:MemoryLayout<NativeVertex>.offset(of:\.color)!),
                    .init(semantic:.uv0,format:.float2,offset:MemoryLayout<NativeVertex>.offset(of:\.uv)!)
                ]
                descriptor.vertexLayouts=[.init(bufferIndex:0,bufferStride:MemoryLayout<NativeVertex>.stride)]
                let resource=try LowLevelMesh(descriptor:descriptor)
                resource.withUnsafeMutableBytes(bufferIndex:0) {target in mesh.vertices.withUnsafeBytes {target.copyMemory(from:$0)}}
                resource.withUnsafeMutableIndices {target in mesh.indices.withUnsafeBytes {target.copyMemory(from:$0)}}
                var low=SIMD3<Float>(repeating:.greatestFiniteMagnitude),high = -low
                for v in mesh.vertices {low=simd_min(low,v.position);high=simd_max(high,v.position)}
                resource.parts.replaceAll([.init(indexCount:mesh.indices.count,topology:.triangle,materialIndex:0,
                    bounds:BoundingBox(min:low-SIMD3(repeating:0.001),max:high+SIMD3(repeating:0.001)))])
                content.addChild(ModelEntity(mesh:try await MeshResource(from:resource),materials:[try await material(mesh.textureID)]))
            }
        }
        @MainActor func capture(_ label:String) async throws -> [UInt8] {
            // Wait for real completed GPU work while shader variants specialize.
            for _ in 0..<30 {
                try await framePump.render()
                completedFrames += 1
                try await Task.sleep(for:.milliseconds(16))
            }
            var pixels=[UInt8](repeating:0,count:size*size*4)
            target.getBytes(&pixels,bytesPerRow:size*4,from:MTLRegionMake2D(0,0,size,size),mipmapLevel:0)
            let info=CGBitmapInfo.byteOrder32Big.rawValue|CGImageAlphaInfo.premultipliedLast.rawValue
            let provider=CGDataProvider(data:Data(pixels) as CFData)!
            let image=CGImage(width:size,height:size,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:size*4,
                space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:info),provider:provider,
                decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
            let file=artifacts.appendingPathComponent("gpu-\(label).png")
            let destination=CGImageDestinationCreateWithURL(file as CFURL,"public.png" as CFString,1,nil)!
            CGImageDestinationAddImage(destination,image,nil)
            require(CGImageDestinationFinalize(destination),"Could not save \(label)")
            return pixels
        }
        func coverage(_ bytes:[UInt8])->[Bool] {
            // The background is deliberately unlike cache model colors. Compare
            // with its actual GPU value to avoid assuming a color-space transfer.
            let background=Array(bytes[0..<3])
            return (0..<size*size).map {p in (0..<3).contains {abs(Int(bytes[p*4+$0])-Int(background[$0]))>2}}
        }
        let examples:[(String,[Int],NativeLighting)]=[
            ("cow",[3341,3342],.actor),
            ("goblin",[2951,2953,2955,2956,2957],.actor),
            ("textured-1003",[1003],.object)
        ]
        for (name,ids,lighting) in examples {
            let parts=[NativeAssetPart(models:ids)]
            let raw=try await NativeComposition.meshes(parts:parts,store:store,lighting:nil)
            let lit=try await NativeComposition.meshes(parts:parts,store:store,lighting:lighting)
            require(raw.count==lit.count && !raw.isEmpty,"\(name): missing material groups")
            for (before,after) in zip(raw,lit) {
                require(before.indices==after.indices && before.textureID==after.textureID && before.vertices.count==after.vertices.count,"\(name): altered topology")
                require(zip(before.vertices,after.vertices).allSatisfy {$0.position==$1.position && $0.uv==$1.uv && $0.color.w==$1.color.w},"\(name): altered geometry/UV/alpha")
            }
            // Change only the viewing transform; original mesh coordinates,
            // winding, UVs and texture data go to the production layout intact.
            let rotation=simd_quatf(angle:0.23,axis:SIMD3(1,0,0))*simd_quatf(angle:Float.pi-0.58,axis:SIMD3(0,1,0))
            var low=SIMD3<Float>(repeating:.greatestFiniteMagnitude),high = -low
            for mesh in raw {for vertex in mesh.vertices {let p=rotation.act(vertex.position);low=simd_min(low,p);high=simd_max(high,p)}}
            let extent=high-low,scale=2.4/max(0.01,max(extent.x,extent.y))
            content.orientation=rotation;content.scale=SIMD3(repeating:scale);content.position = -(low+high)*0.5*scale
            try await upload(raw)
            let before=try await capture(name+"-before")
            try await upload(lit)
            let after=try await capture(name+"-after")
            let beforeMask=coverage(before),afterMask=coverage(after)
            let beforeCount=beforeMask.filter {$0}.count,afterCount=afterMask.filter {$0}.count
            let mismatch=zip(beforeMask,afterMask).filter {$0 != $1}.count
            let common=(0..<beforeMask.count).filter {beforeMask[$0] && afterMask[$0]}
            let changed=common.filter {p in (0..<3).contains {abs(Int(before[p*4+$0])-Int(after[p*4+$0]))>8}}.count
            var colors=Set<Int>()
            for p in common {colors.insert((Int(after[p*4])>>3)<<10 | (Int(after[p*4+1])>>3)<<5 | (Int(after[p*4+2])>>3))}
            require(beforeCount>3000 && afterCount>3000,"\(name): empty or too-small GPU render")
            require(mismatch<=max(24,common.count/200),"\(name): lighting changed coverage (\(mismatch) pixels)")
            require(changed>common.count/20,"\(name): expected visible lighting change, found \(changed)/\(common.count)")
            require(colors.count>=12,"\(name): lit output is flat or a fallback material")
            print("GPU \(name): rawCoverage=\(beforeCount) litCoverage=\(afterCount) coverageMismatch=\(mismatch) changedRGB=\(changed) quantizedLitColors=\(colors.count) completedFrames=\(completedFrames)")
            reports.append(["model":name,"ids":ids,"rawCoverage":beforeCount,"litCoverage":afterCount,"coverageMismatch":mismatch,
                "changedRGBPixels":changed,"quantizedLitColors":colors.count,"completedFrames":completedFrames])
        }
        require(completedFrames==examples.count*60,"Missing completed GPU captures")
        let report:[String:Any]=["platform":"macOS RealityKit offscreen GPU","gpu":device.name,"completedFrames":completedFrames,
            "cases":reports,"limitation":"Production material and vertex-layout proof; visionOS system volume and headset appearance require separate acceptance."]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:artifacts.appendingPathComponent("model-gpu-lighting.json"))
        print("PASS original cow, armed goblin and textured model: unchanged geometry/UV/alpha, matching GPU coverage, visibly shaded colors through production MaterialX and NativeVertex layout")
        print("LIMIT: actual macOS offscreen RealityKit GPU; this does not establish headset appearance, spatial input or display performance")
    }
}
