import Metal
import MetalKit
import SwiftUI
import simd
import CompositorServices
import ARKit
import ImageIO
import CoreGraphics

private struct DrawUniforms {
    var viewProjection:simd_float4x4
    var modelToBoard:simd_float4x4
    var boardToWorld:simd_float4x4
    var tint=SIMD4<Float>(repeating:1)
    var e0=SIMD4<Float>.zero;var e1=SIMD4<Float>.zero;var e2=SIMD4<Float>.zero;var e3=SIMD4<Float>.zero
    var e4=SIMD4<Float>.zero;var e5=SIMD4<Float>.zero;var e6=SIMD4<Float>.zero;var e7=SIMD4<Float>.zero
    var edgeCount:UInt32=0;var textured:UInt32=0;var clipped:UInt32=1;var padding:UInt32=0
    mutating func boundary(_ points:[SIMD2<Float>]) {
        edgeCount=UInt32(min(8,points.count)); var edges=Array(repeating:SIMD4<Float>.zero,count:8)
        for i in 0..<Int(edgeCount) {let a=points[i],b=points[(i+1)%Int(edgeCount)];edges[i]=SIMD4(a.x,a.y,b.x,b.y)}
        e0=edges[0];e1=edges[1];e2=edges[2];e3=edges[3];e4=edges[4];e5=edges[5];e6=edges[6];e7=edges[7]
    }
}
private struct GPUGeometry {
    let vertices:MTLBuffer;let indices:MTLBuffer;let count:Int;let texture:Int
    var lastUse:UInt64
    var byteCount:Int {vertices.length+indices.length}
}
// Shared buffers become writable only after the last command that reads them completes.
private final class GPUCompletionTracker:@unchecked Sendable {
    private let lock=NSLock()
    private var completed:UInt64=0
    func finish(_ serial:UInt64){lock.lock();completed=max(completed,serial);lock.unlock()}
    func read()->UInt64 {lock.lock();defer{lock.unlock()};return completed}
}
final class MetalSceneRenderer: @unchecked Sendable {
    let device:MTLDevice
    let queue:MTLCommandQueue
    private let pipeline:MTLRenderPipelineState
    private let depth:MTLDepthStencilState
    private var geometry:[UUID:GPUGeometry]=[:]
    private var retired:[GPUGeometry]=[]
    private var retiredBytes=0
    private var commandSerial:UInt64=0
    private let completion=GPUCompletionTracker()
    private var textures:[Int:MTLTexture]=[:]
    private let white:MTLTexture
    private let textureLoader:MTKTextureLoader
    private var frame=0
    private var boardKey=""
    private var boardGeometry:RenderGeometry?
    private(set) var frameUploads=0
    private let inflight=DispatchSemaphore(value:3)
    init(device:MTLDevice,color:MTLPixelFormat,depthFormat:MTLPixelFormat = .depth32Float) throws {
        self.device=device
        guard let queue=device.makeCommandQueue(),let url=Bundle.main.resourceURL?.appendingPathComponent("TableScapeShaders.txt") else {throw NativeAssetError.missing("Metal library")}
        let library=try device.makeLibrary(source:String(contentsOf:url,encoding:.utf8),options:nil)
        self.queue=queue
        let descriptor=MTLRenderPipelineDescriptor();descriptor.vertexFunction=library.makeFunction(name:"sc_vertex");descriptor.fragmentFunction=library.makeFunction(name:"sc_fragment")
        descriptor.colorAttachments[0].pixelFormat=color;descriptor.depthAttachmentPixelFormat=depthFormat
        descriptor.colorAttachments[0].isBlendingEnabled=true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .one;descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one;descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        pipeline=try device.makeRenderPipelineState(descriptor:descriptor)
        let dd=MTLDepthStencilDescriptor();dd.depthCompareFunction = .greaterEqual;dd.isDepthWriteEnabled=true;depth=device.makeDepthStencilState(descriptor:dd)!
        textureLoader=MTKTextureLoader(device:device)
        let td=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba8Unorm,width:1,height:1,mipmapped:false)
        white=device.makeTexture(descriptor:td)!
        var color:UInt32=0xffffffff;white.replace(region:MTLRegionMake2D(0,0,1,1),mipmapLevel:0,withBytes:&color,bytesPerRow:4)
    }
    func commandBuffer()->MTLCommandBuffer? {
        guard inflight.wait(timeout:.now()) == .success else{RenderMetrics.shared.miss();return nil}
        guard let buffer=queue.makeCommandBuffer() else{inflight.signal();return nil}
        let start=CACurrentMediaTime()
        commandSerial+=1;let serial=commandSerial
        buffer.addCompletedHandler{[inflight,completion] buffer in
            completion.finish(serial)
            RenderMetrics.shared.record(cpu:max(0,buffer.kernelEndTime-buffer.kernelStartTime),gpu:max(0,buffer.gpuEndTime-buffer.gpuStartTime));inflight.signal()
            if buffer.status == .error {print("TABLESCAPE_GPU_ERROR \(buffer.error?.localizedDescription ?? "Unknown") elapsed=\(CACurrentMediaTime()-start)")}
        }
        return buffer
    }
    func prepare(_ snapshot:RenderSnapshot) {
        frame+=1;frameUploads=0
        let active=Set((snapshot.nodes+snapshot.placementNodes).map{$0.geometry.id})
        let expired=geometry.keys.filter{!active.contains($0) && $0 != boardGeometry?.id}
        for id in expired {
            if let old=geometry.removeValue(forKey:id),retiredBytes+old.byteCount<=32*1024*1024 {
                retired.append(old);retiredBytes+=old.byteCount
            }
        }
        textures=textures.filter{$0.key<100_000 || snapshot.textures[$0.key] != nil}
        for (id,data) in snapshot.textures where textures[id]==nil {
            if let source=CGImageSourceCreateWithData(data as CFData,nil),let original=CGImageSourceCreateImageAtIndex(source,0,nil) {
                let width=original.width,height=original.height
                var rgba=[UInt8](repeating:0,count:width*height*4)
                let bitmap=CGBitmapInfo.byteOrder32Big.rawValue|CGImageAlphaInfo.premultipliedLast.rawValue
                if let context=CGContext(data:&rgba,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:bitmap) {
                    context.draw(original,in:CGRect(x:0,y:0,width:width,height:height))
                    for index in stride(from:0,to:rgba.count,by:4) where rgba[index]==255 && rgba[index+1]==0 && rgba[index+2]==255 {rgba[index]=0;rgba[index+1]=0;rgba[index+2]=0;rgba[index+3]=0}
                    if let provider=CGDataProvider(data:Data(rgba) as CFData),let image=CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:bitmap),provider:provider,decode:nil,shouldInterpolate:true,intent:.defaultIntent),let texture=try? textureLoader.newTexture(cgImage:image,options:[.SRGB:false,.generateMipmaps:true]) {textures[id]=texture}
                }
            }
        }
        let key=snapshot.boundary.map{"\($0.x),\($0.y)"}.joined(separator:";")
        if key != boardKey {
            boardKey=key;var vertices:[NativeVertex]=[],indices:[UInt32]=[]
            let points=snapshot.boundary
            if points.count>=3 {
                let center=points.reduce(SIMD2<Float>.zero,+)/Float(points.count)
                for i in points.indices {
                    let a=points[i],b=points[(i+1)%points.count],innerA=center+(a-center)*0.986,innerB=center+(b-center)*0.986
                    let offset=UInt32(vertices.count)
                    for (p,y) in [(a,Float(-0.008)),(b,Float(-0.008)),(innerB,Float(-0.008)),(innerA,Float(-0.008))] {vertices.append(NativeVertex(position:SIMD3(p.x,y,p.y),color:SIMD4(0.58,0.37,0.15,1)))}
                    indices += [offset,offset+1,offset+2,offset,offset+2,offset+3]
                }
            }
            boardGeometry=RenderGeometry(NativeMesh(vertices:vertices,indices:indices))
        }
    }
    private func upload(_ render:RenderGeometry)->GPUGeometry? {
        if var cached=geometry[render.id] {
            cached.lastUse=commandSerial;geometry[render.id]=cached;return cached
        }
        let mesh=render.mesh
        guard !mesh.vertices.isEmpty,!mesh.indices.isEmpty,frameUploads<24_000_000 else{RenderMetrics.shared.deferredUpload();return nil}
        let vsize=mesh.vertices.count*MemoryLayout<NativeVertex>.stride,isize=mesh.indices.count*4
        guard frameUploads+vsize+isize<=24_000_000 else{RenderMetrics.shared.deferredUpload();return nil}
        let completed=completion.read()
        var best:Int?
        for index in retired.indices {
            let entry=retired[index]
            if entry.lastUse<=completed && entry.vertices.length>=vsize && entry.indices.length>=isize,
               best == nil || entry.byteCount<retired[best!].byteCount {best=index}
        }
        let v:MTLBuffer,i:MTLBuffer
        if let best {
            let reused=retired.remove(at:best);retiredBytes-=reused.byteCount
            v=reused.vertices;i=reused.indices
            RenderMetrics.shared.geometryBuffer(reused:true)
        } else {
            guard let vertices=device.makeBuffer(length:(vsize+255) & ~255,options:.storageModeShared),
                  let indices=device.makeBuffer(length:(isize+255) & ~255,options:.storageModeShared) else{return nil}
            v=vertices;i=indices
            RenderMetrics.shared.geometryBuffer(reused:false)
        }
        mesh.vertices.withUnsafeBytes{source in _ = memcpy(v.contents(),source.baseAddress!,vsize)}
        mesh.indices.withUnsafeBytes{source in _ = memcpy(i.contents(),source.baseAddress!,isize)}
        frameUploads+=vsize+isize
        let result=GPUGeometry(vertices:v,indices:i,count:mesh.indices.count,texture:mesh.textureID,lastUse:commandSerial)
        geometry[render.id]=result;return result
    }
    func encode(_ encoder:MTLRenderCommandEncoder,snapshot:RenderSnapshot,viewProjection:simd_float4x4,board:simd_float4x4,cameraWorld:simd_float4x4,preview:Bool=false) {
        encoder.setRenderPipelineState(pipeline);encoder.setDepthStencilState(depth);encoder.setCullMode(.none)
        var uniforms=DrawUniforms(viewProjection:viewProjection,modelToBoard:matrix_identity_float4x4,boardToWorld:board)
        uniforms.boundary(snapshot.boundary)
        func draw(_ node:RenderNode,model:simd_float4x4,clipped:Bool) {
            guard let gpu=upload(node.geometry) else{return}
            uniforms.modelToBoard=model;uniforms.tint=node.tint;uniforms.clipped=clipped ? 1:0;uniforms.textured=textures[gpu.texture] != nil ? 1:0
            encoder.setVertexBuffer(gpu.vertices,offset:0,index:0)
            encoder.setVertexBytes(&uniforms,length:MemoryLayout<DrawUniforms>.stride,index:1)
            encoder.setFragmentBytes(&uniforms,length:MemoryLayout<DrawUniforms>.stride,index:1)
            encoder.setFragmentTexture(textures[gpu.texture] ?? white,index:0)
            encoder.drawIndexedPrimitives(type:.triangle,indexCount:gpu.count,indexType:.uint32,indexBuffer:gpu.indices,indexBufferOffset:0)
        }
        for node in (preview ? []:snapshot.placementNodes) { uniforms.boardToWorld=matrix_identity_float4x4; draw(node,model:node.transform,clipped:false) }; uniforms.boardToWorld=board
        if let geometry=boardGeometry {draw(RenderNode(geometry:geometry),model:matrix_identity_float4x4,clipped:false)}
        guard snapshot.visible || preview else{return}
        let gameToBoard=snapshot.gameToBoard
        for node in snapshot.nodes {
            if node.billboard {
                let local=scPoint(gameToBoard*node.transform,.zero)
                guard scInside(SIMD2(local.x,local.z),snapshot.boundary) else{continue}
                let position=board*SIMD4(local,1),scale=snapshot.scale
                let matrix=simd_float4x4(cameraWorld.columns.0*scale,cameraWorld.columns.1*scale,cameraWorld.columns.2*scale,position)
                uniforms.boardToWorld=matrix_identity_float4x4;draw(node,model:matrix,clipped:false);uniforms.boardToWorld=board
            } else {draw(node,model:gameToBoard*node.transform,clipped:true)}
        }
    }
}

@MainActor final class PreviewDelegate:NSObject,MTKViewDelegate {
    let scene:GameScene
    var renderer:MetalSceneRenderer?
    var projection=matrix_identity_float4x4
    var eye=SIMD3<Float>(0,1.2,1.6)
    init(scene:GameScene){self.scene=scene;super.init()}
    func mtkView(_ view:MTKView,drawableSizeWillChange size:CGSize){}
    func draw(in view:MTKView) {
        guard let renderer,let descriptor=view.currentRenderPassDescriptor,let drawable=view.currentDrawable,let buffer=renderer.commandBuffer() else{return}
        descriptor.colorAttachments[0].clearColor=MTLClearColor(red:0.025,green:0.045,blue:0.05,alpha:1);descriptor.depthAttachment.clearDepth=0
        let angle=Float(scene.orbit),pitch=Float(scene.tilt),distance:Float=1.02
        eye=SIMD3(sin(angle)*cos(pitch)*distance,sin(pitch)*distance,cos(angle)*cos(pitch)*distance)
        projection=scPerspective(Float.pi/3.1,Float(view.drawableSize.width/max(1,view.drawableSize.height)))*scLookAt(eye,.zero)
        let encodeStart=CACurrentMediaTime()
        let snapshot=scene.exchange.read();renderer.prepare(snapshot)
        if let encoder=buffer.makeRenderCommandEncoder(descriptor:descriptor) {renderer.encode(encoder,snapshot:snapshot,viewProjection:projection,board:matrix_identity_float4x4,cameraWorld:scLookAt(eye,.zero).inverse,preview:true);encoder.endEncoding()}
        RenderMetrics.shared.encode(seconds:CACurrentMediaTime()-encodeStart,bytes:renderer.frameUploads,late:false)
        buffer.present(drawable);buffer.commit()
    }
    @objc func tap(_ gesture:UITapGestureRecognizer) {pick(gesture.location(in:gesture.view),size:gesture.view?.bounds.size ?? .zero,menu:false)}
    @objc func longPress(_ gesture:UILongPressGestureRecognizer) {if gesture.state == .began {pick(gesture.location(in:gesture.view),size:gesture.view?.bounds.size ?? .zero,menu:true)}}
    func pick(_ point:CGPoint,size:CGSize,menu:Bool){
        guard size.width>0,size.height>0 else{return}
        let x=Float(point.x/size.width*2-1),y=Float(1-point.y/size.height*2)
        let far=projection.inverse*SIMD4(x,y,0.001,1),p=SIMD3(far.x,far.y,far.z)/far.w
        scene.pick(origin:eye,direction:simd_normalize(p-eye),preview:true,menu:menu)
    }
}
struct MetalBoardPreview:UIViewRepresentable {
    @ObservedObject var scene:GameScene
    func makeCoordinator()->PreviewDelegate {PreviewDelegate(scene:scene)}
    func makeUIView(context:Context)->MTKView {
        let view=MTKView(frame:.zero,device:MTLCreateSystemDefaultDevice());view.colorPixelFormat = .bgra8Unorm_srgb;view.depthStencilPixelFormat = .depth32Float;view.preferredFramesPerSecond=60
        view.accessibilityIdentifier="world.board";view.accessibilityLabel="TableScape world. Tap to walk or interact. Hold to inspect actions."
        do {if let device=view.device {context.coordinator.renderer=try MetalSceneRenderer(device:device,color:view.colorPixelFormat)}} catch {scene.status="Renderer: \(error.localizedDescription)"}
        view.delegate=context.coordinator
        let tap=UITapGestureRecognizer(target:context.coordinator,action:#selector(PreviewDelegate.tap(_:)))
        let hold=UILongPressGestureRecognizer(target:context.coordinator,action:#selector(PreviewDelegate.longPress(_:)))
        tap.require(toFail:hold);view.addGestureRecognizer(tap);view.addGestureRecognizer(hold);return view
    }
    func updateUIView(_ view:MTKView,context:Context){}
}

struct TableCompositorConfiguration:CompositorLayerConfiguration {
    func makeConfiguration(capabilities:LayerRenderer.Capabilities,configuration:inout LayerRenderer.Configuration) {
        configuration.colorFormat = .bgra8Unorm_srgb;configuration.depthFormat = .depth32Float
        configuration.isFoveationEnabled=false
        let supported=capabilities.supportedLayouts(options:[])
        configuration.layout=supported.contains(.dedicated) ? .dedicated:.layered
    }
}
final class ImmersiveMetalRenderer: @unchecked Sendable {
    let layer:LayerRenderer
    let exchange:SceneExchange
    let tracking:TableTrackingSource
    let renderer:MetalSceneRenderer
    var onInvalidated:(@Sendable ()->Void)?
    init(layer:LayerRenderer,exchange:SceneExchange,tracking:TableTrackingSource) throws {
        self.layer=layer;self.exchange=exchange;self.tracking=tracking
        renderer=try MetalSceneRenderer(device:layer.device,color:layer.configuration.colorFormat,depthFormat:layer.configuration.depthFormat)
    }
    func start(){Thread.detachNewThread{self.run()}}
    private func run(){
        while layer.state != .invalidated {
            if layer.state == .paused {layer.waitUntilRunning();continue}
            autoreleasepool {renderFrame()}
        }
        onInvalidated?()
    }
    private func renderFrame(){
        guard let frame=layer.queryNextFrame() else{return}
        guard let timing=frame.predictTiming() else{return}
        frame.startUpdate()
        let snapshot=exchange.read();renderer.prepare(snapshot)
        frame.endUpdate()
        LayerRenderer.Clock().wait(until:timing.optimalInputTime)
        frame.startSubmission()
        let drawables=frame.queryDrawables()
        guard !drawables.isEmpty else{return}
        let encodeStart=CACurrentMediaTime()
        for drawable in drawables {
            let components=LayerRenderer.Clock.Instant.epoch.duration(to:drawable.frameTiming.presentationTime).components
            let seconds=Double(components.seconds)+Double(components.attoseconds)/1e18
            let anchor=tracking.queryDeviceAnchor(atTimestamp:seconds)
            drawable.deviceAnchor=anchor
            guard let buffer=renderer.commandBuffer() else{continue}
            for (index,view) in drawable.views.enumerated() {
                let map=view.textureMap,descriptor=MTLRenderPassDescriptor()
                descriptor.colorAttachments[0].texture=drawable.colorTextures[map.textureIndex]
                descriptor.colorAttachments[0].slice=map.sliceIndex;descriptor.colorAttachments[0].loadAction = .clear;descriptor.colorAttachments[0].storeAction = .store;descriptor.colorAttachments[0].clearColor=MTLClearColorMake(0,0,0,0)
                descriptor.depthAttachment.texture=drawable.depthTextures[map.textureIndex];descriptor.depthAttachment.slice=map.sliceIndex;descriptor.depthAttachment.loadAction = .clear;descriptor.depthAttachment.storeAction = .store;descriptor.depthAttachment.clearDepth=0
                guard let encoder=buffer.makeRenderCommandEncoder(descriptor:descriptor) else{continue}
                encoder.setViewport(map.viewport)
                let camera=(anchor?.originFromAnchorTransform ?? matrix_identity_float4x4)*view.transform
                let projection=drawable.computeProjection(viewIndex:index)*camera.inverse
                #if targetEnvironment(simulator)
                let boardClip=projection*snapshot.board*SIMD4<Float>(0,0,0,1)
                RenderMetrics.shared.view(["boardNDCX":Double(boardClip.x/boardClip.w),"boardNDCY":Double(boardClip.y/boardClip.w),"boardNDCZ":Double(boardClip.z/boardClip.w),"boardClipW":Double(boardClip.w),"virtual":snapshot.virtual ? 1:0,"visible":snapshot.visible ? 1:0,"nodes":Double(snapshot.nodes.count),"anchor":anchor == nil ? 0:1,"cameraY":Double(camera.columns.3.y),"cameraZ":Double(camera.columns.3.z),"viewY":Double(view.transform.columns.3.y),"viewZ":Double(view.transform.columns.3.z),"boardY":Double(snapshot.board.columns.3.y),"boardZ":Double(snapshot.board.columns.3.z)])
                #endif
                if anchor != nil || snapshot.virtual {renderer.encode(encoder,snapshot:snapshot,viewProjection:projection,board:snapshot.board,cameraWorld:camera)};encoder.endEncoding()
            }
            drawable.encodePresent(commandBuffer:buffer);buffer.commit()
        }
        RenderMetrics.shared.encode(seconds:CACurrentMediaTime()-encodeStart,bytes:renderer.frameUploads,late:LayerRenderer.Clock().now>timing.renderingDeadline)
        frame.endSubmission()
    }
}
