// Appended to the exact production renderer by test-native-terrain-clipping.sh.
// The tests read GPU output, including production projection, clipping, texture
// loading, premultiplied blending, depth and billboard placement.
extension MetalSceneRenderer {
    func checkLowerTerrainClipping(originalWater:Data) throws -> Int {
        let size=512
        let colorDescriptor=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.bgra8Unorm,width:size,height:size,mipmapped:false)
        colorDescriptor.usage=[.renderTarget,.shaderRead];colorDescriptor.storageMode = .shared
        let color=device.makeTexture(descriptor:colorDescriptor)!
        let depthDescriptor=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.depth32Float,width:size,height:size,mipmapped:false)
        depthDescriptor.usage=[.renderTarget];depthDescriptor.storageMode = .private
        let depthTexture=device.makeTexture(descriptor:depthDescriptor)!
        let eye=SIMD3<Float>(0,1.5,2.3),view=scLookAt(eye,SIMD3(0,-0.3,0))
        let projection=scPerspective(.pi/3,1)*view
        let boundary=[SIMD2<Float>(-0.55,-0.55),SIMD2(0.55,-0.55),SIMD2(0.55,0.55),SIMD2(-0.55,0.55)]
        let scale:Float=0.038
        var failures=0,checks=0
        func check(_ condition:Bool,_ label:String) {
            checks+=1
            if !condition { failures+=1;print("FAIL \(label)") }
        }
        func tile(texture:Int = -1,alpha:Float = 1)->RenderNode {
            let vertices:[NativeVertex]=[(-0.85,-0.85),(0.85,-0.85),(0.85,0.85),(-0.85,0.85)].map {x,z in
                NativeVertex(position:SIMD3(Float(x)/scale,0,Float(z)/scale),color:SIMD4(0.15,0.45,0.75,alpha),uv:SIMD2(repeating:0.5))
            }
            return RenderNode(geometry:RenderGeometry(NativeMesh(vertices:vertices,indices:[0,1,2,0,2,3],textureID:texture)))
        }
        func png(_ rgba:[UInt8])->Data {
            let data=Data(rgba),provider=CGDataProvider(data:data as CFData)!
            let info=CGBitmapInfo.byteOrder32Big.rawValue|CGImageAlphaInfo.premultipliedLast.rawValue
            let image=CGImage(width:1,height:1,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:info),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
            let result=NSMutableData()
            let destination=CGImageDestinationCreateWithData(result,"public.png" as CFString,1,nil)!
            CGImageDestinationAddImage(destination,image,nil)
            precondition(CGImageDestinationFinalize(destination))
            return result as Data
        }
        func render(_ snapshot:RenderSnapshot)->[UInt8] {
            prepare(snapshot)
            let command=commandBuffer()!
            let pass=MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture=color;pass.colorAttachments[0].loadAction = .clear;pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor=MTLClearColorMake(0,0,0,0)
            pass.depthAttachment.texture=depthTexture;pass.depthAttachment.loadAction = .clear;pass.depthAttachment.storeAction = .dontCare;pass.depthAttachment.clearDepth=0
            let encoder=command.makeRenderCommandEncoder(descriptor:pass)!
            encode(encoder,snapshot:snapshot,viewProjection:projection,board:matrix_identity_float4x4,cameraWorld:view.inverse)
            encoder.endEncoding();command.commit();command.waitUntilCompleted()
            precondition(command.status == .completed,"GPU render command did not complete")
            var pixels=[UInt8](repeating:0,count:size*size*4)
            color.getBytes(&pixels,bytesPerRow:size*4,from:MTLRegionMake2D(0,0,size,size),mipmapLevel:0)
            return pixels
        }
        func rgba(_ pixels:[UInt8],at point:SIMD3<Float>)->SIMD4<UInt8> {
            let clip=projection*SIMD4(point,1)
            let x=Int((clip.x/clip.w+1)*0.5*Float(size)),y=Int((1-clip.y/clip.w)*0.5*Float(size))
            precondition(x>1 && x<size-2 && y>1 && y<size-2,"Sample outside render target")
            let offset=(y*size+x)*4
            return SIMD4(pixels[offset+2],pixels[offset+1],pixels[offset],pixels[offset+3])
        }
        func alpha(_ pixels:[UInt8],at point:SIMD3<Float>)->UInt8 { rgba(pixels,at:point).w }
        // The same opaque river/terrain patch must survive a player-centered board
        // moving above it. The old shader erased every sample at heights >= 1.
        for height:Float in [0,1,4,15] {
            for reversed in [false,true] {
                var snapshot=RenderSnapshot(nodes:[tile()],center:SIMD3(0,height,0),scale:scale)
                snapshot.boundary=reversed ? boundary.reversed():boundary
                let pixels=render(snapshot),y = -height*scale
                let inside=[SIMD2<Float>(0,0),SIMD2(-0.32,-0.25),SIMD2(0.32,0.25)]
                let outside=[SIMD2<Float>(-0.72,0),SIMD2(0.72,0),SIMD2(0,-0.72),SIMD2(0,0.72)]
                for p in inside {check(alpha(pixels,at:SIMD3(p.x,y,p.y))==255,"opaque lower terrain centerY=\(height) reversed=\(reversed) sample=\(p)")}
                for p in outside {check(alpha(pixels,at:SIMD3(p.x,y,p.y))==0,"outside boundary stays clear centerY=\(height) reversed=\(reversed) sample=\(p)")}
            }
        }
        // Check the unchanged texture policy through the production image loader:
        // opaque water remains opaque; keyed/zero-alpha holes remain transparent;
        // translucent pixels still blend rather than becoming forcibly opaque.
        let textureCases:[(String,[UInt8],Int)]=[("opaque water",[32,96,192,255],255),("transparent cutout",[0,0,0,0],0),("magenta keyed cutout",[255,0,255,255],0),("partial alpha",[64,64,64,128],128)]
        for (index,entry) in textureCases.enumerated() {
            let id=100_001+index
            var snapshot=RenderSnapshot(nodes:[tile(texture:id)],textures:[id:png(entry.1)],center:SIMD3(0,4,0),scale:scale)
            snapshot.boundary=boundary
            let result=Int(alpha(render(snapshot),at:SIMD3(0,-4*scale,0)))
            check(abs(result-entry.2)<=1,"\(entry.0) alpha expected=\(entry.2) actual=\(result)")
        }
        // The original revision-274 river texture follows the same loader and
        // shader path as the synthetic alpha fixtures. The runner validates its
        // bytes against the bundled asset manifest before passing it here.
        var river=RenderSnapshot(nodes:[tile(texture:1)],textures:[1:originalWater],center:SIMD3(0,3,0),scale:scale)
        river.boundary=boundary
        let riverAlpha=alpha(render(river),at:SIMD3(0,-3*scale,0))
        check(riverAlpha==255,"original river texture 1 centerY=3 alpha expected=255 actual=\(riverAlpha)")
        print("Original river texture 1, raised centerY=3: alpha=\(riverAlpha)")
        // Alpha from original geometry remains meaningful too.
        for (input,expected):(Float,Int) in [(0.1,0),(0.5,128)] {
            var snapshot=RenderSnapshot(nodes:[tile(alpha:input)],center:SIMD3(0,4,0),scale:scale)
            snapshot.boundary=boundary
            let result=Int(alpha(render(snapshot),at:SIMD3(0,-4*scale,0)))
            check(abs(result-expected)<=1,"geometry alpha=\(input) expected=\(expected) actual=\(result)")
        }
        // Actor labels/effects also live below the player's elevation. Their
        // separate CPU billboard gate must use the same horizontal footprint.
        let vertices:[NativeVertex]=[SIMD3<Float>(-2,-2,0),SIMD3(2,-2,0),SIMD3(2,2,0),SIMD3(-2,2,0)].map{NativeVertex(position:$0,color:SIMD4(repeating:1))}
        let geometry=RenderGeometry(NativeMesh(vertices:vertices,indices:[0,1,2,0,2,3]))
        for x:Float in [0,0.72] {
            let node=RenderNode(geometry:geometry,transform:scTranslation(SIMD3(x/scale,0,0)),billboard:true)
            var snapshot=RenderSnapshot(nodes:[node],center:SIMD3(0,4,0),scale:scale)
            snapshot.boundary=boundary
            let result=alpha(render(snapshot),at:SIMD3(x,-4*scale,0))
            check(result == (x==0 ? 255:0),"lower billboard x=\(x) alpha=\(result)")
        }
        #if TABLE_ROTATION_CHECKS
        // Rotate asymmetric content about a nonzero game center while the
        // physical table's unequal width/depth remain fixed. Expected positions
        // are enumerated independently of the production transform so a wrong
        // rotation direction or missing center translation fails GPU pixels.
        let gameCenter=SIMD3<Float>(3210,5,3200)
        let fixedBoundary=[SIMD2<Float>(-0.56,-0.26),SIMD2(0.56,-0.26),SIMD2(0.56,0.26),SIMD2(-0.56,0.26)]
        let markerHeight:Float=0.035
        func marker(at point:SIMD2<Float>,color:SIMD4<Float>)->RenderNode {
            let vertices=[SIMD2<Float>(-0.04,-0.025),SIMD2(0.04,-0.025),SIMD2(0.04,0.025),SIMD2(-0.04,0.025)].map { offset in
                let p=point+offset
                return NativeVertex(position:SIMD3(p.x,markerHeight,-p.y)/scale,color:color)
            }
            return RenderNode(geometry:RenderGeometry(NativeMesh(vertices:vertices,indices:[0,1,2,0,2,3])),transform:scTranslation(gameCenter))
        }
        let redPositions=[SIMD2<Float>(0.18,0.07),SIMD2(-0.07,0.18),SIMD2(-0.18,-0.07),SIMD2(0.07,-0.18)]
        let greenPositions=[SIMD2<Float>(0.42,0.04),SIMD2(-0.04,0.42),SIMD2(-0.42,-0.04),SIMD2(0.04,-0.42)]
        var ground=tile();ground.transform=scTranslation(gameCenter)
        let rotatingNodes=[ground,marker(at:redPositions[0],color:SIMD4(1,0.05,0.05,1)),marker(at:greenPositions[0],color:SIMD4(0.05,1,0.05,1))]
        for turn in 0..<4 {
            var snapshot=RenderSnapshot(nodes:rotatingNodes,center:gameCenter,scale:scale)
            snapshot.boundary=fixedBoundary;snapshot.tableQuarterTurns=turn
            let pixels=render(snapshot)
            for (index,position) in redPositions.enumerated() {
                let value=rgba(pixels,at:SIMD3(position.x,markerHeight,position.y))
                let isRed=value.x>240 && value.y<40 && value.z<40 && value.w==255
                check(isRed == (index==turn),"clockwise rotation \(turn*90)° red marker at quadrant=\(index) rgba=\(value)")
            }
            let greenPosition=greenPositions[turn]
            let green=rgba(pixels,at:SIMD3(greenPosition.x,markerHeight,greenPosition.y))
            if turn%2==0 {
                check(green.y>240 && green.x<40 && green.z<40 && green.w==255,"rotation \(turn*90)° outer green marker inside fixed wide edge rgba=\(green)")
            } else {
                check(green.w==0,"rotation \(turn*90)° outer green marker clipped at fixed short edge rgba=\(green)")
            }
            for x:Float in [-0.48,0.48] {
                check(alpha(pixels,at:SIMD3(x,0,0))==255,"rotation \(turn*90)° fixed wide edge remains filled x=\(x)")
            }
            for z:Float in [-0.42,0.42] {
                check(alpha(pixels,at:SIMD3(0,0,z))==0,"rotation \(turn*90)° fixed short edge stays clipped z=\(z)")
            }
        }
        let rotationCoverage=", four clockwise turns within a fixed rectangular board"
        #else
        let rotationCoverage=""
        #endif
        print("\(failures==0 ? "PASS":"FAIL") production Metal terrain clipping: \(checks) pixel checks, \(failures) failures; raised centers 0/1/4/15, both polygon windings, texture/geometry alpha, lower billboards\(rotationCoverage)")
        return failures
    }
}
@main struct NativeTerrainClippingChecks {
    static func main() throws {
        guard let device=MTLCreateSystemDefaultDevice() else {throw NativeAssetError.missing("A real Metal device is required")}
        print("Metal device: \(device.name)")
        let renderer=try MetalSceneRenderer(device:device,color:.bgra8Unorm)
        guard CommandLine.arguments.count==2 else {throw NativeAssetError.missing("Pass the manifest-verified original river texture path")}
        let water=try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))
        if try renderer.checkLowerTerrainClipping(originalWater:water)>0 {exit(1)}
    }
}
